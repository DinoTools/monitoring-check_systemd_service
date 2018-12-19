#!/usr/bin/perl
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings FATAL => 'all';

use constant OK         => 0;
use constant WARNING    => 1;
use constant CRITICAL   => 2;
use constant UNKNOWN    => 3;

# Service state
use constant INACTIVE => 0;
use constant ACTIVE   => 1;

my $pkg_nagios_available = 0;
my $pkg_monitoring_available = 0;

BEGIN {
    eval {
        require Monitoring::Plugin;
        require Monitoring::Plugin::Functions;
        $pkg_monitoring_available = 1;
    };
    if (!$pkg_monitoring_available) {
        eval {
            require Nagios::Plugin;
            require Nagios::Plugin::Functions;
            *Monitoring::Plugin:: = *Nagios::Plugin::;
            $pkg_nagios_available = 1;
        };
    }
    if (!$pkg_monitoring_available && !$pkg_nagios_available) {
        print("UNKNOWN - Unable to find module Monitoring::Plugin or Nagios::Plugin\n");
        exit UNKNOWN;
    }
}

my $mp = Monitoring::Plugin->new(
    shortname => "check_systemd_service",
    usage     => ""
);

$mp->add_arg(
    spec     => 'critical|c=i',
    help     => 'N units can be inactive',
    default  => 1
);

$mp->add_arg(
    spec     => 'warning|w=i',
    help     => 'N units can be inactive',
    default  => 1
);

$mp->add_arg(
    spec     => 'unit=s@',
    help     => 'Name of the unit',
    required => 1,
    default  => []
);

$mp->getopts;

my $inactive_count = 0;
my $message = '';
my $code = OK;
foreach my $unit_name (@{$mp->opts->unit}) {
  my ($status, $msg) = check_unit($unit_name);
  if ($message ne '') {
    $message .= '; ';
  }
  $message .= $msg;

  if ($status != ACTIVE) {
    $inactive_count++;
  }
}

$mp->add_perfdata(
    label => 'count',
    value => scalar @{$mp->opts->unit}
);

if ($inactive_count >= $mp->opts->warning) {
  $code = WARNING;
}
if ($inactive_count >= $mp->opts->critical) {
  $code = CRITICAL;
}

wrap_exit($code, $message);

sub wrap_exit
{
    if($pkg_monitoring_available == 1) {
        $mp->plugin_exit( @_ );
    } else {
        $mp->nagios_exit( @_ );
    }
}

sub check_unit
{
    my ($unit_name) = @_;
    if($unit_name !~ m/.*\..*/) {
        $unit_name .= '.service'
    }
    my $output = `busctl call org.freedesktop.systemd1 /org/freedesktop/systemd1 org.freedesktop.systemd1.Manager LoadUnit s "$unit_name"`;
    my $unit_object_name;
    my %values = (
        ActiveEnterTimestamp => undef,
        ActiveState          => undef,
        SubState             => undef,
    );
    if ($output =~ /o "(.*?)"/) {
        $unit_object_name = $1;
        my @value_names = keys %values;
        my $cmd_value_names = join(" ", @value_names);
        $output = `busctl get-property org.freedesktop.systemd1 $unit_object_name org.freedesktop.systemd1.Unit $cmd_value_names`;
        open my $fh, '<', \$output or wrap_exit(UNKNOWN, sprintf('There was an error "%s"', $!));
        my $line;
        foreach my $value_name (@value_names) {
            if(eof($fh)) {
                last;
                wrap_exit(
                    UNKNOWN,
                    'Command did not return the values we expected'
                );
            }
            $line = readline($fh);
            if ($line =~ /^s "(.*?)"$/) {
                $values{$value_name} = $1;
            } elsif ($line =~ /^t ([0-9]+)$/) {
                $values{$value_name} = $1;
            } else {
                wrap_exit(
                    UNKNOWN,
                    sprintf('Unable to parse response %s', $line)
                );
            }
        }
        close $fh or wrap_exit(UNKNOWN, sprintf('There was an error "%s"', $!));

        my $status = INACTIVE;
        my $active_time = 0;
        if ($values{'ActiveState'} =~ m/^(active|reloading|activating)$/) {
            $status = ACTIVE;
            $active_time = time() - int($values{'ActiveEnterTimestamp'} / 1000000)
        }
        $mp->add_perfdata(
            label     => sprintf('%s current active time', $unit_name),
            value     => $active_time,
            uom       => 's'
        );
        return(
          $status,
          sprintf('%s: %s(%s)', $unit_name, $values{ActiveState}, $values{SubState})
        );
    }
}
