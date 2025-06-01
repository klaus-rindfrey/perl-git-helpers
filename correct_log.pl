#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long qw(:config no_ignore_case auto_help auto_version);

use Pod::Usage;

our $VERSION = '1.00.02';

my ($Old_Mail, $New_Mail, $New_User, $No_Credentials);

GetOptions('old_email|oe=s'  => \$Old_Mail,
           'new_email|ne=s'  => \$New_Mail,
           'new_user|nu=s'   => \$New_User,
           'not_settings|nc' => \$No_Credentials
          ) or pod2usage(2);

$Old_Mail // die("'--old_email' missing.");
$New_Mail // die("'--new_email' missing.");
$New_User // die("'--new_user' missing.");

my $Filter_Branch = <<"EOT";
git filter-branch --env-filter '
OLD_EMAIL="$Old_Mail"
CORRECT_NAME="$New_User"
CORRECT_EMAIL="$New_Mail"

if [ "\$GIT_COMMITTER_EMAIL" = "\$OLD_EMAIL" ]
then
    export GIT_COMMITTER_NAME="\$CORRECT_NAME"
    export GIT_COMMITTER_EMAIL="\$CORRECT_EMAIL"
fi
if [ "\$GIT_AUTHOR_EMAIL" = "\$OLD_EMAIL" ]
then
    export GIT_AUTHOR_NAME="\$CORRECT_NAME"
    export GIT_AUTHOR_EMAIL="\$CORRECT_EMAIL"
fi
' --tag-name-filter cat -- --branches --tags
EOT
#Don't append a semicolon to the line above!

my @Commands = ('echo "--- Correct local git history ---"',
                $Filter_Branch,

                'echo "--- Clean up local repo ---"',
                'rm -rf .git/refs/original/',
                'git reflog expire --expire=now --all',
                'git gc --prune=now --aggressive',

                'echo "--- push changes to github ---"',
                "git push --force --tags origin 'refs/heads/*'",
                $No_Credentials ? () : (
                                        'echo "--- Set credentials ---"',
                                        'git config credential.helper store',
                                        "git config user.email $New_Mail",
                                        "git config user.name \$New_User"
                                       )
               );


# https://chatgpt.com/c/670d4141-4bf0-8010-97db-0ca53f5f122c


foreach my $cmd (@Commands) {
  chomp($cmd);
  if ($cmd =~ /^echo /) {
    print("\n\n");
  } else {
    my $cmd_msg = $cmd;
    $cmd_msg =~ s/\n/\n          /sg;
    print("Running:  $cmd_msg\n");
  }
  system($cmd) == 0 or die("$cmd --- failed: $!\n");
}

__END__

=pod


=head1 NAME

  correct_log.sh - Change username and email address in git history

=head1 SYNOPSIS

  correct_log.pl --old_email OLD_EMAIL --new_email NEW_EMAIL --new_user NEW_USER [--not_settings]
  correct_log.pl --help | --version

or, shorter:

  correct_log.sh --oe OLD_EMAIL --ne NEW_EMAIL --nu NEW_USER --nc


=head1 DESCRIPTION

In case that you are using an incorrect username and/or email address in a Git
repository, you can use this script to correct the Git log.

Change to your git repo directory and run the scrpt like this:

  correct_log.sh --old_email OLD_EMAIL --new_email NEW_EMAIL --new_user NEW_USER

The options can be written shorter like this:

  correct_log.sh --oe OLD_EMAIL --ne NEW_EMAIL --nu NEW_USER

By default, the script also stores C<NEW_EMAIL> and C<NEW_USER> cia C<git
config credential.helper store>. This can be switched off by specifying the
C<--not_settings> (or C<--nc>) option.


=head1 LICENSE AND COPYRIGHT

This software is copyright (c) 2025 by Klaus Rindfrey.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.


=cut


