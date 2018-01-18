=head1 NAME

 iMSCP::Providers::Service::Debian::Upstart - Upstart service provider for Debian like distributions.

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

package iMSCP::Providers::Service::Debian::Upstart;

use strict;
use warnings;
use Carp qw/ croak /;
use parent qw/ iMSCP::Providers::Service::Upstart iMSCP::Providers::Service::Debian::Sysvinit /;

=head1 DESCRIPTION

 Upstart service provider for Debian like distributions.
 
 Difference with the iMSCP::Providers::Service::Upstart is the support for the
 SysVinit scripts.

 See: https://wiki.debian.org/Upstart

=head1 PUBLIC METHODS

=over 4

=item isEnabled( $job )

 See iMSCP::Providers::Service::Interface::isEnabled()

=cut

sub isEnabled
{
    my ($self, $job) = @_;

    defined $job or croak( 'parameter $job is not defined' );

    return $self->SUPER::isEnabled( $job ) if $self->_isUpstart( $job );

    $self->iMSCP::Providers::Service::Debian::Sysvinit::isEnabled( $job );
}

=item enable( $job )

 See iMSCP::Providers::Service::Interface::enable()

=cut

sub enable
{
    my ($self, $job) = @_;

    defined $job or croak( 'parameter $job is not defined' );

    if ( $self->_isUpstart( $job ) ) {
        return 0 unless $self->SUPER::enable( $job );
    }

    # Enable the underlying SysVinit script if any
    return $self->iMSCP::Providers::Service::Debian::Sysvinit::enable( $job ) if $self->_isSysvinit( $job );

    1;
}

=item disable( $job )

 See iMSCP::Providers::Service::Interface::disable()

=cut

sub disable
{
    my ($self, $job) = @_;

    defined $job or croak( 'parameter $job is not defined' );

    if ( $self->_isUpstart( $job ) ) {
        return 0 unless $self->SUPER::disable( $job );
    }

    # Disable the underlying SysVinit script if any
    return $self->iMSCP::Providers::Service::Debian::Sysvinit::disable( $job ) if $self->_isSysvinit( $job );

    1;
}

=item remove( $job )

 See iMSCP::Providers::Service::Interface::remove()

=cut

sub remove
{
    my ($self, $job) = @_;

    defined $job or croak( 'parameter $job is not defined' );

    if ( $self->_isUpstart( $job ) ) {
        return 0 unless $self->SUPER::remove( $job );
    }

    # Remove the underlying SysVinit script if any
    $self->iMSCP::Providers::Service::Debian::Sysvinit::remove( $job );
}

=item hasService( $service )

 See iMSCP::Providers::Service::Interface::hasService()

=cut

sub hasService
{
    my ($self, $job) = @_;

    defined $job or croak( 'parameter $service is not defined' );

    $self->SUPER::hasService( $job ) || $self->iMSCP::Providers::Service::Debian::Sysvinit::hasService( $job );
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__