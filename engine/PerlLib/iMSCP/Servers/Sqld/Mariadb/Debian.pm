=head1 NAME

 iMSCP::Servers::Sqld::Mariadb::Debian - i-MSCP (Debian) MariaDB SQL server implementation

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

package iMSCP::Servers::Sqld::Mariadb::Debian;

use strict;
use warnings;
use autouse 'iMSCP::Crypt' => qw/ decryptRijndaelCBC /;
use autouse 'iMSCP::Execute' => qw/ execute /;
use autouse 'iMSCP::TemplateParser' => qw/ processByRef /;
use Carp qw/ croak /;
use Class::Autouse qw/ :nostat iMSCP::Dir iMSCP::File /;
use File::Temp;
use iMSCP::Database;
use iMSCP::Debug qw/ debug error /;
use iMSCP::Service;
use version;
use parent 'iMSCP::Servers::Sqld::Mysql::Debian';

our $VERSION = '1.0.0';

=head1 DESCRIPTION

 i-MSCP (Debian) MariaDB SQL server implementation.

=head1 PUBLIC METHODS

=over 4

=item postinstall( )

 See iMSCP::Servers::Sqld::postinstall()

=cut

sub postinstall
{
    my ($self) = @_;

    eval { iMSCP::Service->getInstance()->enable( 'mariadb' ); };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    $self->{'eventManager'}->registerOne(
        'beforeSetupRestartServices',
        sub {
            push @{$_[0]}, [ sub { $self->restart(); }, $self->getHumanServerName() ];
            0;
        },
        $self->getPriority()
    );
}

=item uninstall( )

 Process uninstall tasks

 Return int 0 on success, other on failure

=cut

sub uninstall
{
    my ($self) = @_;

    my $rs = $self->_removeConfig();
    return $rs if $rs;

    eval {
        my $serviceMngr = iMSCP::Service->getInstance();
        $serviceMngr->restart( 'mariadb' ) if $serviceMngr->hasService( 'mariadb' ) && $serviceMngr->isRunning( 'mariadb' );
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=item start( )

 See iMSCP::Servers::Abstract::start()

=cut

sub start
{
    my ($self) = @_;

    eval { iMSCP::Service->getInstance()->start( 'mariadb' ); };
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

    eval { iMSCP::Service->getInstance()->stop( 'mariadb' ); };
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

    eval { iMSCP::Service->getInstance()->restart( 'mariadb' ); };
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

    eval { iMSCP::Service->getInstance()->reload( 'mariadb' ); };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=item getHumanServerName( )

 See iMSCP::Servers::Sqld::Mysql::Abstract::getHumanServerName()

=cut

sub getHumanServerName
{
    my ($self) = @_;

    sprintf( 'MariaDB %s', $self->getVersion());
}

=item createUser( $user, $host, $password )

 See iMSCP::Servers::Sqld::Mysql::Abstract::createUser()

=cut

sub createUser
{
    my (undef, $user, $host, $password) = @_;

    defined $user or croak( '$user parameter is not defined' );
    defined $host or croak( '$host parameter is not defined' );
    defined $password or croak( '$password parameter is not defined' );

    eval {
        my $dbh = iMSCP::Database->getInstance()->getRawDb();
        local $dbh->{'RaiseError'} = 1;

        unless ( $dbh->selectrow_array( 'SELECT EXISTS(SELECT 1 FROM mysql.user WHERE User = ? AND Host = ?)', undef, $user, $host ) ) {
            # User doesn't already exist. We create it
            $dbh->do( 'CREATE USER ?@? IDENTIFIED BY ?', undef, $user, $host, $password );
        } else {
            $dbh->do( 'SET PASSWORD FOR ?@? = PASSWORD(?)', undef, $user, $host, $password );
        }
    };
    !$@ or croak( sprintf( "Couldn't create/update the %s\@%s SQL user: %s", $user, $host, $@ ));
    0;
}

=back

=head1 PRIVATE METHODS

=over 4

=item _setVendor( )

 See iMSCP::Servers::Sqld::Mysql::Abstract::_setVendor()

=cut

sub _setVendor
{
    my ($self) = @_;

    debug( sprintf( 'SQL server vendor set to: %s', 'MariaDB' ));
    $self->{'config'}->{'SQLD_VENDOR'} = 'MariaDB';
    0;
}

=item _buildConf( )

 See iMSCP::Servers::Sqld::Mysql::Abstract::_buildConf()

=cut

sub _buildConf
{
    my ($self) = @_;

    eval {
        # Make sure that the conf.d directory exists
        iMSCP::Dir->new( dirname => "$self->{'config'}->{'SQLD_CONF_DIR'}/conf.d" )->make( {
            user  => $main::imscpConfig{'ROOT_USER'},
            group => $main::imscpConfig{'ROOT_GROUP'},
            mode  => 0755
        } );
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    # Build the my.cnf file
    my $rs = $self->{'eventManager'}->registerOne(
        'beforeMysqlBuildConfFile',
        sub {
            unless ( defined ${$_[0]} ) {
                ${$_[0]} = "!includedir $_[5]->{'SQLD_CONF_DIR'}/conf.d/\n";
            } elsif ( ${$_[0]} !~ m%^!includedir\s+$_[5]->{'SQLD_CONF_DIR'}/conf.d/\n%m ) {
                ${$_[0]} .= "!includedir $_[5]->{'SQLD_CONF_DIR'}/conf.d/\n";
            }

            0;
        }
    );
    $rs ||= $self->buildConfFile(
        ( -f "$self->{'config'}->{'SQLD_CONF_DIR'}/my.cnf" ? "$self->{'config'}->{'SQLD_CONF_DIR'}/my.cnf" : File::Temp->new() ),
        "$self->{'config'}->{'SQLD_CONF_DIR'}/my.cnf", undef, undef, { srcname => 'my.cnf' }
    );
    return $rs if $rs;

    # Build the imscp.cnf file
    my $conffile = File::Temp->new();
    print $conffile <<'EOF';
# Configuration file - auto-generated by i-MSCP
#     DO NOT EDIT THIS FILE BY HAND -- YOUR CHANGES WILL BE OVERWRITTEN
[mysql]
max_allowed_packet = {MAX_ALLOWED_PACKET}
[mysqld]
event_scheduler = {EVENT_SCHEDULER}
innodb_use_native_aio = {INNODB_USE_NATIVE_AIO}
max_connections = {MAX_CONNECTIONS}
max_allowed_packet = MAX_ALLOWED_PACKET}
performance_schema = {PERFORMANCE_SCHEMA}
sql_mode = {SQL_MODE}
EOF
    $conffile->close();
    $rs ||= $self->buildConfFile( $conffile, "$self->{'config'}->{'SQLD_CONF_DIR'}/conf.d/imscp.cnf", undef,
        {
            EVENT_SCHEDULER       => 'DISABLED',
            INNODB_USE_NATIVE_AIO => $main::imscpConfig{'SYSTEM_VIRTUALIZER'} eq 'physical' ? 'ON' : 'OFF',
            MAX_CONNECTIONS       => '500',
            MAX_ALLOWED_PACKET    => '500M',
            PERFORMANCE_SCHEMA    => 'OFF',
            SQL_MODE              => ''
        },
        {
            mode    => 0644,
            srcname => 'imscp.cnf'
        }
    );
}

=item _updateServerConfig( )

 See iMSCP::Servers::Sqld::Mysql::Abstract::_updateServerConfig()

=cut

sub _updateServerConfig
{
    my ($self) = @_;

    # Upgrade MySQL tables if necessary

    {
        my $defaultExtraFile = File::Temp->new();
        print $defaultExtraFile <<'EOF';
[mysql_upgrade]
host = {HOST}
port = {PORT}
user = "{USER}"
password = "{PASSWORD}"
EOF
        $defaultExtraFile->close();
        my $rs = $self->buildConfFile( $defaultExtraFile, $defaultExtraFile, undef,
            {
                HOST     => main::setupGetQuestion( 'DATABASE_HOST' ),
                PORT     => main::setupGetQuestion( 'DATABASE_PORT' ),
                USER     => main::setupGetQuestion( 'DATABASE_USER' ) =~ s/"/\\"/gr,
                PASSWORD => decryptRijndaelCBC( $main::imscpKEY, $main::imscpIV, main::setupGetQuestion( 'DATABASE_PASSWORD' )) =~ s/"/\\"/gr
            },
            { srcname => 'default-extra-file' }
        );
        return $rs if $rs;

        $rs = execute( "/usr/bin/mysql_upgrade --defaults-extra-file=$defaultExtraFile", \my $stdout, \my $stderr );
        debug( $stdout ) if $stdout;
        error( sprintf( "Couldn't upgrade SQL server system tables: %s", $stderr || 'Unknown error' )) if $rs;
        return $rs if $rs;
    }

    # Disable unwanted plugins

    return 0 if version->parse( $self->getVersion()) < version->parse( '10.0' );

    eval {
        my $dbh = iMSCP::Database->getInstance()->getRawDb();
        local $dbh->{'RaiseError'};

        # Disable unwanted plugins (bc reasons)
        for ( qw/ cracklib_password_check simple_password_check unix_socket validate_password / ) {
            $dbh->do( "UNINSTALL PLUGIN $_" ) if $dbh->selectrow_hashref( "SELECT name FROM mysql.plugin WHERE name = '$_'" );
        }
    };
    if ( $@ ) {
        error( $@ );
        return 1;
    }

    0;
}

=back

=head1 AUTHOR

 Laurent Declercq <l.declercq@nuxwin.com>

=cut

1;
__END__