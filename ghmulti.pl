#!/usr/bin/env perl

use strict;
use warnings;
use autodie;

use File::Spec::Functions;

use Getopt::Std;


our $VERSION = '1.00.00';


my %Opts;
getopts('cu', \%Opts );

die("Too many options") if keys(%Opts) > 1;

if ($Opts{u}) {
  my $url = @ARGV ? shift : get_remote_url();
  die("Too many arguments") if @ARGV;
  print (get_ssh_url($url), "\n");
} elsif ($Opts{c}) {
  die("Missing URL") if !@ARGV;
  die("Too many arguments") if @ARGV > 2;
  clone_repo(@ARGV);
} else {
  die("Too many arguments") if @ARGV;
  config_existing_repo();
}


# --- subroutines ------------------------------------------------------------

#
# clone_repo GITHUB_REPO, DIR
# clone_repo GITHUB_REPO
#
# Clones GITHUB_REPO and configures the local clone with the data from ‘~/.ssh/config’.
#
sub clone_repo {
  my ($url, $dir) = @_;
  exit_with_msg("You are in a git repo", 1) if in_git_repo();
  my ($uname, $repo) = get_data_from_gh_url($url);
  $dir //= $repo;
  my $user_data = get_user_data($uname);
  run_cmd("git clone " . get_ssh_url($url) . " $dir");
  chdir($dir);
  config_user_data($user_data);  #config_existing_repo();
  chdir("..");
}


#
# config_existing_repo
#
# Configures the current git repo with the data from ‘~/.ssh/config’. If the
# remote url is already in 'git@github-...' the function prints a message and
# does nothing.
#
sub config_existing_repo {
  my $url = get_remote_url();
  exit_with_msg("Remote URL is already 'git\@github-' format") if $url =~ /^git\@github-/;
  my ($uname, undef) = get_data_from_gh_url($url);
  my $user_data = get_user_data($uname);
  run_cmd("git remote set-url origin " . get_ssh_url($url));
  config_user_data($user_data);
}


#
# get_user_data USER_NAME
#
# Reads ‘~/.ssh/config’ and returns a hasg consisting containing the user's
# full name ('full_name') and e-mail address ('email') from this file.
#
sub get_user_data {
  my $user_name = shift;
  my $config_file = catfile($ENV{HOME}, qw(.ssh config));

  open(my $hndl, '<', $config_file);
  my %seen;
  my $cfg_data;
  while (defined(my $line = <$hndl>)) {
    if ($line =~ /^Host\s+github-(\S+)\s*$/) {
      my $current_user_name = $1;
      die("$current_user_name: duplicate user name") if exists($seen{$current_user_name});
      $seen{$current_user_name} = undef;
      $line = <$hndl> // die("$config_file: unexpected EOF.\n");
      $line =~ /^\s*#\s*User:\s*(?:(\S+(?:\s+\S+)*)\s*)?<(\S+)>/ or
        die("Missing or invalid user info");
      if ($current_user_name eq $user_name) {
        $cfg_data = {
                     full_name => $1 // $current_user_name,
                     email     => $2
                    };
        last;
      }
    }
  }
  close($hndl);
  exit_with_msg("$user_name: user name not in $config_file") unless $cfg_data;
  return $cfg_data;
}


#
# get_ssh_url GITHUB_URL
#
# Changes GITHUB_URL in our 'git\@github-...' format and returns the result.
#
sub get_ssh_url {
  my $url = shift;
  return $url if $url =~ /^git\@github-/;
  my ($uname, $repo) = get_data_from_gh_url($url);
  return "git\@github-$uname:$uname/$repo.git";
}


#
# get_data_from_gh_url GITHUB_URL
#
# Returns a two-element list containing user name and repo taken from GITHUB_URL.
#
sub get_data_from_gh_url {
  my $url = shift;
  if ($url =~ s!^https://github\.com/([\w-]+)/!!              ||
      $url =~ s!^https://([\w-]+):\w+\@github\.com/[\w-]+/!!  ||
      $url =~ s!^git\@github\.com:([\w-]+)/!!                 ||
      $url =~ s!^git\@github-[\w-]+:([\w-]+)/!!               # Our 'Host' format.
     ) {
    my $uname = $1;
    $url =~ s/\.git$//;
    return ($uname, $url);
  } else {
    die("$url: unrecognized URL");
  }
}


#
# in_git_repo
#
# Returns a boolean that flags if you are in a git repo.
#
sub in_git_repo {
  `git status 2>&1`;
  return $? == 0;
}


#
# get_remote_url
#
# Returns the remote url. If you are not in a git repo, the sub terminates
# with an error message.
#
sub get_remote_url {
  exit_with_msg("Not in a git repo", 1) unless in_git_repo();
  my $url = `git remote get-url origin`;
  if ($?) {
    die("Failed to execute get-url");
  }
  chomp($url);
  return $url;
}


#
# config_user_data UDATA
#
# Locally configures user.email and user.name.
# UDATA is a reference to a hash containing 'email' and 'full_name'.
#
sub config_user_data {
  my ($udata) = @_;
  run_cmd("git config user.email \"$udata->{email}\"");
  run_cmd("git config user.name \"$udata->{full_name}\"");
}

# ---

#
# exit_with_msg MSG, EXIT_VALUE
# exit_with_msg MSG
#
# Prints MSG and exits with value EXIT_VALUE (default: 0).
# For EXIT_VALUE != 0 the message is printed to STDERR.
#
sub exit_with_msg {
  my ($msg, $exit_value) = @_;
  $exit_value //= 0;
  my $hndl = $exit_value ? *STDERR : *STDOUT;
  $msg .= "\n" if substr($msg, -1) ne "\n";
  print $hndl ($msg);
  exit $exit_value;
}


#
# run_cmd CMD ECHO
# run_cmd CMD
#
# Executes CMD.
#
# If ECHO is a true value, then CMD is also printed to STDOUT. Default is true (1).
#
sub run_cmd {
  my ($cmd, $echo) = @_;
  $echo //= 1;
  chomp($cmd);
  print("Running: $cmd\n") if $echo;
  system($cmd) == 0 or croak("Failed running  $cmd");
}



__END__


=pod


=head1 NAME

ghmulti.sh - Helps when using multiple Github accounts with SSH keys


=head1 SYNOPSIS

   ghmulti.sh [ -c GITHUB_URL [DIR] | -u [GITHUB_URL] ]
   ghmulti.sh --help | --version

=head1 DESCRIPTION

This script helps when using multiple Github accounts with SSH keys. First,
you should read this gist
L<https://gist.github.com/oanhnn/80a89405ab9023894df7> and follow the
instructions.

To use this script, you need to add information in file F</.ssh/config> by
adding comments like this:

   Host github-foo
   #  User: John Doe <jd@foomail.com>
      HostName github.com
      IdentityFile ~/.ssh/foo
      IdentitiesOnly yes

   Host github-bar
   #  User: Mr. Smith <somename@blahmail.org>
      HostName github.com
      IdentityFile ~/.ssh/bar
      IdentitiesOnly yes

   Host github-baz
   #  User: <abc@blubb.eu>
      HostName github.com
      IdentityFile ~/.ssh/baz
      IdentitiesOnly yes

The script looks for C<Host> names beginning with C<github->. It assumes that
the part after the hyphen is your username on github. E.g., in the example
above the gibthub usernames are C<foo>, C<bar> and C<baz>.

The next line must be a comment line beginning with C<User:> followed by an
optional name (full name, may contain spaces) followed by an email address in angle
brackets. The script uses this data like this

  git config user.email EMAIL
  git config user.name  FULLNAME

If you did not specify a full name, the script uses your github user name instead.

These are the variants of how you can use the script:

=over

=item * Without any arguments

If you are in a git repo, the script sets the remote URL to use the SSH key
and configures the email address and the username as described above.
Otherwise the script terminates with an error state.

=item * C<-c GITHUB_URL [DIR]>

This works like C<git clone> but also configures the repo as described above.

=item * C<-u [GITHUB_URL]>

Prints the github URL in the format needed to use your SSH keys. If
I<C<GITHUB_URL>> is not specified, the script attempts to determine a URL via
C<git remote get-url origin>.

With this option, the script does not an configuration.

=back

Note: the options C<-c> and C<-u> are mutually exclusive!


=head1 ACKNOWLEDGEMENTS

Many thanks to Oanh Nguyen (oanhnn) for publishing this gist:
L<https://gist.github.com/oanhnn/80a89405ab9023894df7>, and to everyone who
contributed in the comments.


=head1 LICENSE AND COPYRIGHT

This software is copyright (c) 2025 by Klaus Rindfrey.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.


=cut

