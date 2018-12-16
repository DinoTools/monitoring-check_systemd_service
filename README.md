check_systemd_service
=====================

Check if a systemd unit is active and report the current active time as perf data.

Requriements
------------

**General**

- Perl 5
- Perl Modules:
    - Monitoring::Plugin or Nagios::Plugin

**RHEL/CentOS**

- perl
- perl-Monitoring-Plugin or perl-Nagios-Plugin

Installation
------------

Just copy the file `check_systemd_service.pl` to your Icinga or Nagios plugin directory.

**Icinga 2**

Add a new check command

```
object CheckCommand "systemd_service" {
  import "plugin-check-command"
  import "ipv4-or-ipv6"

  command = [ PluginDir + "/check_systemd_service.pl" ]

  arguments = {
    "--unit" = {
      value = "$systemd_service_unit$"
      description = "Name of the unit to check"
      required = true
      repeat_key = true
    }
  }
}
```

License
-------

GPLv3+
