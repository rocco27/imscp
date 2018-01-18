=head1 NAME

 iMSCP::Providers::Service::Upstart - Upstart base service provider implementation

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2018 by Laurent Declercq <l.declercq@nuxwin.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

package iMSCP::Providers::Service::Upstart;

use strict;
use warnings;
use Carp qw/ croak /;
use File::Basename;
use File::Spec;
use iMSCP::File;
use version;
use parent 'iMSCP::Providers::Service::Sysvinit';

# Commands used in that package
our %COMMANDS = (
    start   => '/sbin/start',
    stop    => '/sbin/stop',
    restart => '/sbin/restart',
    reload  => '/sbin/reload',
    status  => '/sbin/status',
    initctl => '/sbin/initctl'
);

# Private variables
my $UPSTART_VERSION;
my $START_ON = qr/^\s*start\s+on/;
my $COMMENTED_START_ON = qr/^\s*#+\s*start\s+on/;
my $MANUAL = qr/^\s*manual\s*/m;

# Paths where job files must be searched
my @JOBFILEPATHS = ( '/etc/init' );

# Operate against system upstart, not session (see See IP-1514)
delete $ENV{'UPSTART_SESSION'};

=head1 DESCRIPTION

 Upstart base service provider implementation.

 See: http://upstart.ubuntu.com

=head1 PUBLIC METHODS

=over 4

=item isEnabled( $job )

 See iMSCP::Providers::Service::Interface::isEnabled()

=cut

sub isEnabled
{
    my ($self, $job) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );

    return $self->_isEnabledPre067( $self->_readJobFile( $job )) if $self->_versionIsPre067();
    return $self->_isEnabledPre090( $self->_readJobFile( $job )) if $self->_versionIsPre090();

    $self->_isEnabledPost090( $self->_readJobFile( $job ), $self->_readJobOverrideFile( $job ));
}

=item enable( $job )

 See iMSCP::Providers::Service::Interface::enable()

=cut

sub enable
{
    my ($self, $job) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );

    return $self->_enablePre090( $job, $self->_readJobFile( $job )) if $self->_versionIsPre090();

    $self->_enablePost090( $job, $self->_readJobFile( $job ), $self->_readJobOverrideFile( $job ));
}

=item disable( $job )

 See iMSCP::Providers::Service::Interface::disable()

=cut

sub disable
{
    my ($self, $job) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );

    return $self->_disablePre067( $job, $self->_readJobFile( $job )) if $self->_versionIsPre067();
    return $self->_disablePre090( $job, $self->_readJobFile( $job )) if $self->_versionIsPre090();

    $self->_disablePost090( $job, $self->_readJobOverrideFile( $job ));
}

=item remove( $job )

 See iMSCP::Providers::Service::Interface::remove()

=cut

sub remove
{
    my ($self, $job) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );

    return 1 unless $self->_isUpstart( $job );
    return 0 unless $self->stop( $job );

    for ( qw/ conf override / ) {
        if ( my $jobFilePath = eval { $self->getJobFilePath( $job, $_ ); } ) {
            return 0 if iMSCP::File->new( filename => $jobFilePath )->delFile();
        }
    }

    1;
}

=item start( $job )

 See iMSCP::Providers::Service::Interface::start()

=cut

sub start
{
    my ($self, $job) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );

    if ( $self->_isUpstart( $job ) ) {
        return $self->_exec( [ $COMMANDS{'start'}, $job ] ) == 0 unless $self->isRunning( $job );
        return 1;
    }

    $self->SUPER::start( $job );
}

=item stop( $job )

 See iMSCP::Providers::Service::Interface::stop()

=cut

sub stop
{
    my ($self, $job) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );

    if ( $self->_isUpstart( $job ) ) {
        return $self->_exec( [ $COMMANDS{'stop'}, $job ] ) == 0 if $self->isRunning( $job );
        return 1;
    }

    $self->SUPER::stop( $job );
}

=item restart( $job )

 See iMSCP::Providers::Service::Interface::restart()

=cut

sub restart
{
    my ($self, $job) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );

    if ( $self->_isUpstart( $job ) ) {
        return $self->_exec( [ $COMMANDS{'restart'}, $job ] ) == 0 if $self->isRunning( $job );
        return $self->start( $job );
    }

    $self->SUPER::restart( $job );
}

=item reload( $job )

 See iMSCP::Providers::Service::Interface::reload()

=cut

sub reload
{
    my ($self, $job) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );

    if ( $self->_isUpstart( $job ) ) {
        if ( $self->isRunning( $job ) ) {
            # We need catch STDERR here as we do do want report it as error
            my $ret = $self->_exec( [ $COMMANDS{'reload'}, $job ], undef, \ my $stderr ) == 0;
            return $self->restart( $job ) unless $ret; # Reload failed. Try a restart instead.
            return $ret;
        }

        return $self->start( $job );
    }

    $self->SUPER::reload( $job );
}

=item isRunning( $job )

 See iMSCP::Providers::Service::Interface::isRunning()

=cut

sub isRunning
{
    my ($self, $job) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );

    if ( $self->_isUpstart( $job ) ) {
        $self->_exec( [ $COMMANDS{'status'}, $job ], \ my $stdout );
        return $stdout =~ /start/;
    }

    $self->SUPER::isRunning( $job );
}

=item hasService( $job )

 See iMSCP::Providers::Service::Interface::hasService()

=cut

sub hasService
{
    my ($self, $job) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );

    $self->_isUpstart( $job );
}

=item getJobFilePath( $job [, $jobFileType = 'conf' ] )

 Get full path of the job configuration file or job override file that belongs to the given job

 Param string $job Job name
 Param string $jobFileType OPTIONAL Job file type (conf|override) - Default to 'conf'
 Return string job file path on success, croak on failure

=cut

sub getJobFilePath
{
    my ($self, $job, $jobFileType) = @_;
    $jobFileType //= 'conf';

    defined $job or croak( 'Missing or undefined $job parameter' );

    $self->_searchJobFile( $job, $jobFileType );
}

=back

=head1 PRIVATE METHODS

=over 4

=item _getVersion( )

 Get upstart version

 Return string Upstart version

=cut

sub _getVersion
{
    ( $UPSTART_VERSION ) = `initctl --version` =~ /initctl \(upstart\s+([^\)]*)\)/ unless $UPSTART_VERSION;
    $UPSTART_VERSION;
}

=item _isUpstart( $job )

 Is the given job an upstart job?

 Param string $job Job name
 Return bool TRUE if the given job is managed by an upstart job, FALSE otherwise

=cut

sub _isUpstart
{
    my ($self, $job) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );

    eval { $self->_searchJobFile( $job ); };
}

=item _versionIsPre067( )

 Is upstart version pre 0.6.7?

 Return bool TRUE if upstart version is pre 0.6.7, FALSE otherwise

=cut

sub _versionIsPre067
{
    my ($self) = @_;

    version->parse( $self->_getVersion()) < version->parse( '0.6.7' );
}

=item _versionIsPre090( )

 Is upstart version pre 0.9.0?

 Return bool TRUE if upstart version is pre 0.9.0, FALSE otherwise

=cut

sub _versionIsPre090
{
    my ($self) = @_;

    version->parse( $self->_getVersion()) < version->parse( '0.9.0' );
}

=item _versionIsPost090( )

 Is upstart version post 0.9.0?

 Return bool TRUE if upstart version is post 0.9.0, FALSE otherwise

=cut

sub _versionIsPost090
{
    my ($self) = @_;

    version->parse( $self->_getVersion()) >= version->parse( '0.9.0' );
}

=item _isEnabledPre067( $jobFileContent )

 Is the given job enabled for upstart versions < 0.6.7?

 Param string $jobFileContent job file content
 Return bool TRUE if the given job is enabled, FALSE otherwise

=cut

sub _isEnabledPre067
{
    my (undef, $jobFileContent) = @_;

    defined $jobFileContent or croak( 'Missing or undefined $jobFileContent parameter' );

    # Upstart version < 0.6.7 means no `manual' stanza.
    $jobFileContent =~ /$START_ON/;
}

=item _isEnabledPre090( $jobFileContent )

 Is the given job enabled for upstart versions < 0.9.0?

 Param string $jobFileContent job file content
 Return bool TRUE if the given job is enabled, FALSE otherwise

=cut

sub _isEnabledPre090
{
    my (undef, $jobFileContent) = @_;

    defined $jobFileContent or croak( 'Missing or undefined $jobFileContent parameter' );

    # Upstart versions < 0.9.0 means no override files. Thus,
    # we check to see if an uncommented `start on' or `manual'
    # stanza is the last one in the file. The last one in the
    # file wins.
    open my $fh, '<', \$jobFileContent or croak ( sprintf( "Couldn't open in-memory file handle: %s", $! ));
    my $enabled = 0;
    while ( <$fh> ) {
        if ( /$START_ON/ ) {
            $enabled = 1;
        } elsif ( /$MANUAL/ ) {
            $enabled = 0;
        }
    }

    $enabled;
}

=item _isEnabledPost090( $jobFileContent, $jobOverrideFileContent )

 Is the given job enabled for upstart versions >= 0.9.0?

 Param string $jobFileContent job file content
 Param string $jobOverrideFileContent job override file content
 Return bool TRUE if the given job is enabled, FALSE otherwise

=cut

sub _isEnabledPost090
{
    my (undef, $jobFileContent, $jobOverrideFileContent) = @_;

    defined $jobFileContent or croak( 'Missing or undefined $jobFileContent parameter' );
    defined $jobOverrideFileContent or croak( 'Missing or undefined $jobOverrideFileContent parameter' );

    # Upstart versions >= 0.9.0 has `manual' stanzas and override
    # files. Thus, we check to see if an uncommented `start on' or
    # `manual' stanza is the last one in the conf file and any
    # override files. The last one in the file wins.
    my $enabled = 0;
    for ( \$jobFileContent, \$jobOverrideFileContent ) {
        open my $fh, '<', $_ or croak ( sprintf( "Couldn't open in-memory file handle: %s", $! ));
        while ( <$fh> ) {
            if ( /$START_ON/ ) {
                $enabled = 1;
            } elsif ( /$MANUAL/ ) {
                $enabled = 0;
            }
        }
    }

    $enabled;
}

=item _enablePre090( $job, $jobFileContent )

 Enable the given job for upstart versions < 0.9.0

 Param string $job Job name
 Param string $jobFileContent job file content
 Return bool TRUE on success, croak on failure

=cut

sub _enablePre090
{
    my ($self, $job, $jobFileContent) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );
    defined $jobFileContent or croak( 'Missing or undefined $jobFileContent parameter' );

    # Remove `manual' stanzas if any
    $jobFileContent = $self->_removeManualStanzaFrom( $jobFileContent );

    # Add or uncomment `START ON' stanza if needed
    unless ( $self->_isEnabledPre090( $jobFileContent ) ) {
        $jobFileContent = ( $jobFileContent =~ /$COMMENTED_START_ON/ )
            ? $self->_uncommentStartOnStanzaIn( $jobFileContent )
            : $self->_addDefaultStartOnStanzaTo( $jobFileContent );
    }

    return $self->_writeFile( $job, $jobFileContent );
}

=item _enablePost090( $job, $jobFileContent, $jobOverrideFileContent )

 Enable the given job for upstart versions >= 0.9.0

 Param string $job Job name
 Param string $jobFileContent job file content
 Param string $jobOverrideFileContent job override file content
 Return bool TRUE on success, croak on failure

=cut

sub _enablePost090
{
    my ($self, $job, $jobFileContent, $jobOverrideFileContent) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );
    defined $jobFileContent or croak( 'Missing or undefined $jobFileContent parameter' );
    defined $jobOverrideFileContent or croak( 'Missing or undefined $jobOverrideFileContent parameter' );

    # Remove `manual' stanzas if any
    $jobOverrideFileContent = $self->_removeManualStanzaFrom( $jobOverrideFileContent );

    # Add or uncomment `START ON' stanza if needed
    unless ( $self->_isEnabledPost090( $jobFileContent, $jobOverrideFileContent ) ) {
        if ( $jobFileContent =~ /$START_ON/ ) {
            $jobOverrideFileContent .= $self->_extractStartOnStanzaFrom( $jobFileContent );
        } else {
            $jobOverrideFileContent = $self->_addDefaultStartOnStanzaTo( $jobOverrideFileContent );
        }
    }

    $self->_writeFile( $job . '.override', $jobOverrideFileContent );
}

=item _disablePre067( $service, $jobFileContent )

 Disable the given job for upstart versions < 0.6.7

 Param string $job Job name
 Param string $jobFileContent job file content
 Return bool TRUE on success, croak on failure

=cut

sub _disablePre067
{
    my ($self, $job, $jobFileContent) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );
    defined $jobFileContent or croak( 'Missing or undefined $jobFileContent parameter' );

    $jobFileContent = $self->_commentStartOnStanza( $jobFileContent );
    $self->_writeFile( $job . '.conf', $jobFileContent );
}

=item _disablePre090( $service, $jobFileContent )

 Disable the given job for upstart versions < 0.9.0

 Param string $job Job name
 Param string $jobFileContent job file content
 Return bool TRUE on success, croak on failure

=cut

sub _disablePre090
{
    my ($self, $job, $jobFileContent) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );
    defined $jobFileContent or croak( 'Missing or undefined $jobFileContent parameter' );

    $self->_writeFile( $job . '.conf', $self->_ensureDisabledWithManualStanza( $jobFileContent ));
}

=item _disablePost090( $service, $jobOverrideFileContent )

 Disable the given job for upstart versions >= 0.9.0

 Param string $job Job name
 Param string $jobOverrideFileContent job $jobOverrideFileContent file content
 Return bool TRUE on success, croak on failure

=cut

sub _disablePost090
{
    my ($self, $job, $jobOverrideFileContent) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );
    defined $jobOverrideFileContent or croak( 'Missing or undefined $jobOverrideFileContent parameter' );

    $self->_writeFile( $job . '.override', $self->_ensureDisabledWithManualStanza( $jobOverrideFileContent ));
}

=item _uncomment( $line )

 Uncomment the given line

 Param string $line
 Return string Uncommented line

=cut

sub _uncomment
{
    my (undef, $line) = @_;

    defined $line or croak( 'Missing or undefined $line parameter' );

    $line =~ s/^(\s*)#+/$1/r;
}

=item _removeTrailingCommentsFromCommentedLine( $line )

 Remove any trailing comments from the given commented line

 Param string $line Line to process
 Return string

=cut

sub _removeTrailingCommentsFromCommentedLine
{
    my (undef, $line) = @_;

    defined $line or croak( 'Missing or undefined $line parameter' );

    $line =~ s/^(\s*#+\s*[^#]*).*/$1/r;
}

=item _removeTrailingComments( $line )

 Remove any trailing comments from the given line

 Param string $line Line to process
 Return string String without any trailing comments

=cut

sub _removeTrailingComments
{
    my (undef, $line) = @_;

    defined $line or croak( 'Missing or undefined $line parameter' );

    $line =~ s/^(\s*[^#]*).*/$1/r;
}

=item _countUnbalancedRoundBrackets( $line )

 Count number of unbalanced round brackets in the given line

 Param string $line Line to process
 Return int Number of unbalanced round brackets

=cut

sub _countUnbalancedRoundBrackets
{
    my (undef, $line) = @_;

    defined $line or croak( 'Missing or undefined $line parameter' );

    ( $line =~ tr/(// )-( $line =~ tr/)// );
}

=item _removeManualStanzaFrom( $string )

 Remove any upstart `manual' stanza from the given $string

 Param string $string String to process
 Return string String without upstart `manual' stanza

=cut

sub _removeManualStanzaFrom
{
    my (undef, $line) = @_;

    defined $line or croak( 'Missing or undefined $line parameter' );

    $line =~ s/$MANUAL//gr;
}

=item _commentStartOnStanza( $text )

 Comment any upstart `start on' stanza in the given text

 Param string $text Text to process
 Return string Text with commented upstart `start on' stanza if any

=cut

sub _commentStartOnStanza
{
    my ($self, $text) = @_;

    defined $text or croak( 'Missing or undefined $text parameter' );

    my $roundBrackets = 0;

    join '',
        map {
            if ( $roundBrackets > 0 || /$START_ON/ ) {
                # If there are more opening round brackets than closing
                # round brackets, we need to comment out a multiline
                # `start on' stanza
                $roundBrackets += $self->_countUnbalancedRoundBrackets( $self->_removeTrailingComments( $_ ));
                '#' . $_;
            } else {
                $_;
            }
        } split /^/, $text;
}

=item _uncommentStartOnStanzaIn( $text )

 Uncomment any upstart `start on' stanza in the given text

 Param string Text to process
 Return string Text with uncommented upstart `start on' stanza if any

=cut

sub _uncommentStartOnStanzaIn
{
    my ($self, $text) = @_;

    defined $text or croak( 'Missing or undefined $text parameter' );

    my $roundBrackets = 0;
    join '',
        map {
            if ( $roundBrackets > 0 || /$COMMENTED_START_ON/ ) {
                # If there are more opening round brackets than closing
                # round brackets, we need to comment out a multiline
                # `start on' stanza
                $roundBrackets += $self->_countUnbalancedRoundBrackets(
                    $self->_removeTrailingCommentsFromCommentedLine( $_ )
                );
                $self->_uncomment( $_ );
            } else {
                $_;
            }
        } split /^/, $text;
}

=item _extractStartOnStanzaFrom( $string )

 Extract the upstart `start on' stanza from the given string if any

 Param string $string String to process
 Return string Text without any upstart `start in stanza'

=cut

sub _extractStartOnStanzaFrom
{
    my ($self, $string) = @_;

    defined $string or croak( 'Missing or undefined $string parameter' );

    my $roundBrackets = 0;
    join '',
        map {
            if ( $roundBrackets > 0 || /$START_ON/ ) {
                $roundBrackets += $self->_countUnbalancedRoundBrackets( $self->_removeTrailingComments( $_ ));
                $_;
            }
        } split /^/, $string;
}

=item _addDefaultStartOnStanzaTo( $string )

 Add default upstart `start on' stanza to the given string

 Param string $string String into which default `start on' stanza must be added
 Return string Text with upstart default `start on' stanza

=cut

sub _addDefaultStartOnStanzaTo
{
    my (undef, $string) = @_;

    defined $string or croak( 'Missing or undefined $string parameter' );

    $string . "\nstart on runlevel [2345]\n";
}

=item _ensureDisabledWithManualStanza( $string )

 Ensure that the given string contains the upstart `manual' stanza

 Param string $string String to process
 Return string String with upstart `manual' stanza

=cut

sub _ensureDisabledWithManualStanza
{
    my ($self, $string) = @_;

    defined $string or croak( 'Missing or undefined $string parameter' );

    $self->_removeManualStanzaFrom( $string ) . "manual\n";
}

=item _searchJobFile( $job, $jobFileType )

 Search the job configuration file or job override file which belongs to the given job in all available paths

 Param string $job Job name
 Param string $jobFileType Job file type ('conf'|'override')
 Return string Job file path on success, croak on failure

=cut

sub _searchJobFile
{
    my (undef, $job, $jobFileType) = @_;
    $jobFileType //= 'conf';

    defined $job or croak( 'Missing or undefined $job parameter' );

    my $jobFile = $job . '.' . $jobFileType;

    for my $path( @JOBFILEPATHS ) {
        my $filepath = File::Spec->join( $path, $jobFile );
        return $filepath if -f $filepath;
    }

    croak( sprintf( "Couldn't find the upstart `%s' job file", $jobFile ));
}

=item _readJobFile( $job )

 Read the job file which belongs to the given job

 Param string $job Job name
 Return string Job file content on success, croak on failure

=cut

sub _readJobFile
{
    my ($self, $job) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );

    my $filepath = $self->getJobFilePath( $job );
    iMSCP::File->new( filename => $filepath )->get() or croak( sprintf( "Couldn't read the `%s' file", $filepath ));
}

=item _readJobOverrideFile( $job )

 Read the job override file which belongs to the given job

 Param string job Job name
 Return string Job override file content on success, croak on failure

=cut

sub _readJobOverrideFile
{
    my ($self, $job) = @_;

    defined $job or croak( 'Missing or undefined $job parameter' );

    my $filepath = eval { $self->getJobFilePath( $job, 'override' ) };
    return '' unless defined $filepath;

    my $fileContent = iMSCP::File->new( filename => $filepath )->get();
    defined $fileContent or croak( sprintf( "Couldn't read the `%s' file", $filepath ));
    $fileContent;
}

=item _writeFile( $filename, $fileContent )

 Write the given job file (job configuration file or job override file)

 Param string $filename file name
 Param string $fileContent file content
 Return bool TRUE on success, croak on failure

=cut

sub _writeFile
{
    my ($self, $filename, $fileContent) = @_;

    defined $filename or croak( 'Missing or undefined $filename parameter' );
    defined $fileContent or croak( 'Missing or undefined $fileContent parameter' );

    my $jobDir = dirname( $self->getJobFilePath( basename( $filename, '.conf', '.override' )));
    my $filepath = File::Spec->join( $jobDir, $filename );
    my $file = iMSCP::File->new( filename => $filepath );

    if ( $fileContent ne '' ) {
        $file->set( $fileContent );
        $file->save() == 0 && $file->mode( 0644 ) == 0 or croak( sprintf( "Couldn't write the `%s' file", $filepath ));
    } elsif ( $filepath =~ /\.override$/ && -f $filepath ) {
        $file->delFile() == 0 or croak( sprintf( "Couldn't unlink the `%s' file", $filepath ));
    } else {
        1;
    }
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__