=head1 NAME

 iMSCP::Servers::Po::Dovecot::Debian - i-MSCP (Debian) Dovecot IMAP/POP3 server implementation

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

package iMSCP::Servers::Po::Dovecot::Debian;

use strict;
use warnings;
use autouse Fcntl => qw/ O_RDONLY /;
use autouse 'File::Basename' => qw/ fileparse /;
use autouse 'iMSCP::Execute' => qw/ execute /;
use autouse 'iMSCP::Rights' => qw/ setRights /;
use autouse 'iMSCP::TemplateParser' => qw/ processByRef /;
use Array::Utils qw/ unique /;
use Carp qw/ croak /;
use Class::Autouse qw/ :nostat iMSCP::Database /;
use iMSCP::Config;
use iMSCP::Debug qw/ debug error getMessageByType /;
use iMSCP::Dir;
use iMSCP::File;
use iMSCP::Getopt;
use iMSCP::Service;
use iMSCP::Umask;
use iMSCP::Servers::Mta;
use iMSCP::Servers::Sqld;
use Sort::Naturally;
use Tie::File;
use iMSCP::Service;
use parent 'iMSCP::Servers::Po::Dovecot::Abstract';

our $VERSION = '1.0.0';

=head1 DESCRIPTION

 i-MSCP (Debian) Dovecot IMAP/POP3 server implementation.

=head1 PUBLIC METHODS

=over 4

=item install( )

 Process install tasks

 Return int 0 on success, other on failure

=cut

sub install
{
    my ($self) = @_;

    my $rs = $self->SUPER::install();
    $rs ||= $self->_cleanup();
}

=item preinstall( )

 See iMSCP::Servers::Po::Dovecot::Abstract::preinstall()

=cut

sub preinstall
{
    my ($self) = @_;

    eval {
        my $serviceMngr = iMSCP::Service->getInstance();

        # Disable dovecot.socket unit if any
        # Dovecot as configured by i-MSCP doesn't rely on systemd activation socket
        # This also solve problem on boxes where IPv6 is not available; default dovecot.socket unit file make
        # assumption that IPv6 is available without further checks...
        # See also: https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=814999
        if ( $serviceMngr->isSystemd() && $serviceMngr->hasService( 'dovecot.socket' ) ) {
            $serviceMngr->stop( 'dovecot.socket' );
            $serviceMngr->disable( 'dovecot.socket' );
        }
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    $self->SUPER::preinstall();
}

=item postinstall( )

 Process postinstall tasks

 Return int 0 on success, other on failure

=cut

sub postinstall
{
    my ($self) = @_;

    eval { iMSCP::Service->getInstance()->enable( 'dovecot' ); };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    $self->SUPER::postinstall();
}

=item uninstall( )

 See iMSCP::Servers::Po::Dovecot::Abstract::uninstall()

=cut

sub uninstall
{
    my ($self) = @_;

    my $rs = $self->SUPER::uninstall();
    return $rs if $rs;

    eval {
        my $serviceMngr = iMSCP::Service->getInstance();
        $serviceMngr->restart( 'dovecot' ) if $serviceMngr->hasService( 'dovecot' ) && $serviceMngr->isRunning( 'dovecot' );
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=item dpkgPostInvokeTasks()

 See iMSCP::Servers::Abstract::dpkgPostInvokeTasks()

=cut

sub dpkgPostInvokeTasks
{
    my ($self) = @_;

    return 0 unless -x '/usr/sbin/dovecot';

    $self->_setVersion();
}

=item start( )

 See iMSCP::Servers::Abstract::start()

=cut

sub start
{
    my ($self) = @_;

    eval { iMSCP::Service->getInstance()->start( 'dovecot' ); };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=item stop( )

 See iMSCP::Servers::Abstract::stop()

=cut

sub stop
{
    my ($self) = @_;

    eval { iMSCP::Service->getInstance()->stop( 'dovecot' ); };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=item restart( )

 See iMSCP::Servers::Abstract::restart()

=cut

sub restart
{
    my ($self) = @_;

    eval { iMSCP::Service->getInstance()->restart( 'dovecot' ); };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=item reload( )

 See iMSCP::Servers::Abstract::reload()

=cut

sub reload
{
    my ($self) = @_;

    eval { iMSCP::Service->getInstance()->reload( 'dovecot' ); };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=back

=head1 PRIVATE METHOD

=over 4

=item _setVersion( )

 See iMSCP::Servers::Dovecot::Abstract::_setVersion()

=cut

sub _setVersion
{
    my ($self) = @_;

    my $rs = execute( [ '/usr/sbin/dovecot', '--version' ], \ my $stdout, \ my $stderr );
    error( $stderr || 'Unknown error' ) if $rs;
    return $rs if $rs;

    if ( $stdout !~ m/^([\d.]+)/ ) {
        error( "Couldn't guess Dovecot version from the `/usr/sbin/dovecot --version` command output" );
        return 1;
    }

    $self->{'config'}->{'DOVECOT_VERSION'} = $1;
    debug( sprintf( 'Dovecot version set to: %s', $1 ));
    0;
}

=item _cleanup( )

 Process cleanup tasks

 Return int 0 on success, other on failure

=cut

sub _cleanup
{
    my ($self) = @_;

    return 0 unless version->parse( $main::imscpOldConfig{'PluginApi'} ) < version->parse( '1.5.1' );

    if ( -f "$self->{'config'}->{'DOVECOT_CONF_DIR'}/dovecot-dict-sql.conf" ) {
        my $rs = iMSCP::File->new( filename => "$self->{'config'}->{'DOVECOT_CONF_DIR'}/dovecot-dict-sql.conf" )->delFile();
        return $rs if $rs;
    }

    eval { iMSCP::Dir->new( dirname => "$self->{'cfgDir'}/$_" ) for qw/ backup working /; };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    return 0 unless -f "$self->{'cfgDir'}/dovecot.old.data";

    iMSCP::File->new( filename => "$self->{'cfgDir'}/dovecot.old.data" )->delFile();
}

=item _shutdown( $priority )

 See iMSCP::Servers::Abstract::_shutdown()

=cut

sub _shutdown
{
    my ($self, $priority) = @_;

    return unless my $action = $self->{'restart'} ? 'restart' : ( $self->{'reload'} ? 'reload' : undef );

    iMSCP::Service->getInstance()->registerDelayedAction( 'dovecot', [ $action, sub { $self->$action(); } ], $priority );
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__