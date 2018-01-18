=head1 NAME

 iMSCP::Servers::Sqld - Factory and abstract implementation for the i-MSCP sqld servers

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

package iMSCP::Servers::Sqld;

use strict;
use warnings;
use Carp qw/ croak /;
use parent 'iMSCP::Servers::Abstract';

=head1 DESCRIPTION

 This class provides a factory and an abstract implementation for the i-MSCP sqld servers.

=head1 CLASS METHODS

=over 4

=item getPriority( )

 Get server priority

 Return int Server priority

=cut

sub getPriority
{
    400;
}

=back

=head1 PUBLIC METHODS

=over 4

=item postinstall( )

 See iMSCP::Servers::Abstract::postinstall()

=cut

sub postinstall
{
    my ($self) = @_;

    $self->{'eventManager'}->registerOne(
        'beforeSetupRestartServices',
        sub {
            push @{$_[0]}, [ sub { $self->restart(); }, $self->getHumanServerName() ];
            0;
        },
        $self->getPriority()
    );

    0;
}

=item getVendor( )

 Get SQL server vendor

 Return string MySQL server vendor

=cut

sub getVendor
{
    my ($self) = @_;

    $self->{'config'}->{'SQLD_VENDOR'};
}

=item getVersion( )

 See iMSCP::Servers::Abstract::getVersion()

=cut

sub getVersion
{
    my ($self) = @_;

    $self->{'config'}->{'SQLD_VERSION'};
}

=item createUser( $user, $host, $password )

 Create the given SQL user if it doesn't already exist, update it password otherwise

 Param $string $user SQL username
 Param string $host SQL user host
 Param $string $password SQL user password
 Return int 0 on success, croak on failure

=cut

sub createUser
{
    my ($self) = @_;

    croak ( sprintf( 'The %s class must implement the createUser() method', ref $self ));
}

=item dropUser( $user, $host )

 Drop the given SQL user if exists

 Param $string $user SQL username
 Param string $host SQL user host
 Return int 0 on success, croak on failure

=cut

sub dropUser
{
    my ($self) = @_;

    croak ( sprintf( 'The %s class must implement the dropUser() method', ref $self ));
}

=back

=head1 PRIVATE METHODS

=over

=item _init( )

 See iMSCP::Servers::Abstract::_init()

=cut

sub _init
{
    my ($self) = @_;

    ref $self ne __PACKAGE__ or croak( sprintf( 'The %s class is an abstract class which cannot be instantiated', __PACKAGE__ ));

    $self->SUPER::_init();
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__