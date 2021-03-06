=head1 NAME

 Servers::sqld::mariadb - i-MSCP MariaDB server implementation

=cut

# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2019 by Laurent Declercq <l.declercq@nuxwin.com>
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

package Servers::sqld::mariadb;

use strict;
use warnings;
use Class::Autouse qw/ :nostat Servers::sqld::mariadb::installer Servers::sqld::mariadb::uninstaller /;
use iMSCP::Boolean;
use iMSCP::Service;
use iMSCP::Database;
use iMSCP::Debug qw/ debug error /;
use Try::Tiny;
use parent 'Servers::sqld::mysql';

=head1 DESCRIPTION

 i-MSCP MariaDB server implementation.

=head1 PUBLIC METHODS

=over 4

=item preinstall( )

 Process preinstall tasks

 Return int 0 on success, other on failure

=cut

sub preinstall
{
    my ( $self ) = @_;

    my $rs = $self->{'eventManager'}->trigger( 'beforeSqldPreinstall', 'mariadb' );
    $rs ||= Servers::sqld::mariadb::installer->getInstance()->preinstall();
    $rs ||= $self->{'eventManager'}->trigger( 'afterSqldPreinstall', 'mariadb' )
}

=item postinstall( )

 Process postinstall tasks

 Return int 0

=cut

sub postinstall
{
    my ( $self ) = @_;

    try {
        my $rs = $self->{'eventManager'}->trigger( 'beforeSqldPostInstall', 'mariadb' );
        return $rs if $rs;

        iMSCP::Service->getInstance()->enable( 'mysql' );

        $rs = $self->{'eventManager'}->register(
            'beforeSetupRestartServices',
            sub {
                push @{ $_[0] }, [ sub { $self->restart(); }, 'MariaDB' ];
                0;
            },
            7
        );
        $rs ||= $self->{'eventManager'}->trigger( 'afterSqldPostInstall', 'mariadb' );
    } catch {
        error( $_ );
        1;
    }
}

=item uninstall( )

 Process uninstall tasks

 Return int 0 on success, other on failure

=cut

sub uninstall
{
    my ( $self ) = @_;

    my $rs = $self->{'eventManager'}->trigger( 'beforeSqldUninstall', 'mariadb' );
    $rs ||= Servers::sqld::mariadb::uninstaller->getInstance()->uninstall();
    $rs ||= $self->{'eventManager'}->trigger( 'afterSqldUninstall', 'mariadb' );
}

=item createUser( $user, $host, $password )

 Create the given SQL user

 Param $string $user SQL username
 Param string $host SQL user host
 Param $string $password SQL user password
 Return int 0 on success, die on failure

=cut

sub createUser
{
    my ( undef, $user, $host, $password ) = @_;

    length $user or die( 'Missing or invalid $user parameter' );
    length $host or die( 'Missing or invalid $host parameter' );
    length $password or die( 'Missing or invalid $password parameter' );

    iMSCP::Database->factory()->getConnector()->run( fixup => sub {
        if ( $_->selectrow_hashref( 'SELECT 1 FROM mysql.user WHERE user = ? AND host = ?', undef, $user, $host ) ) {
            debug( sprintf( 'Updating %s@%s SQL user password', $user, $host ));
            $_->do( 'SET PASSWORD FOR ?@? = PASSWORD(?)', undef, $user, $host, $password );
            return;
        }

        debug( sprintf( 'Creating %s@%s SQL user', $user, $host ));
        $_->do( 'CREATE USER ?@? IDENTIFIED BY ?', undef, $user, $host, $password );
    } );
    0;
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__
