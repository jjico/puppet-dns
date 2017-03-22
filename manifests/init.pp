# == Class: dns
#
# Using custom types untill next stdlib release
class dns (
  Optional[String]              $default_tsig_name = undef,
  Tea::Ipv4                     $default_ipv4      = $::dns::params::default_ipv4,
  Tea::Ipv6                     $default_ipv6      = $::dns::params::default_ipv6,
  Integer[1,256]                $server_count      = $::dns::params::server_count,
  Pattern[/^(nsd|knot)$/]       $daemon            = $::dns::params::daemon,
  String                        $nsid              = $::dns::params::nsid,
  String                        $identity          = $::dns::params::identity,
  Array[Tea::Ip_address]        $ip_addresses      = $::dns::params::ip_addresses,
  Boolean                       $master            = false,
  String                        $instance          = 'default',
  Pattern[/^(present|absent)$/] $ensure            = 'present',
  Tea::Port                     $port              = 53,
  Boolean                       $enable_zonecheck  = true,
  Hash[String, Dns::Zone]       $zones             = {},
  Hash                          $files             = {},
  Hash                          $tsigs             = {},
  Hash                          $remotes           = {},
  Boolean                       $enable_nagios     = false,
) inherits dns::params {
  #class { '::dns::zonecheck':
  #  enable       => $enable_zonecheck,
  #  ip_addresses => $ip_addresses,
  #  zones        => $zones,
  #  tsig         => $tsig,
  #}

  if $daemon == 'nsd' {
    $nsd_enable  =  true
    $knot_enable =  false
    file {'/usr/local/bin/dns-control':
      ensure => link,
      target => '/usr/sbin/nsd-control',
    }
  } else {
    $nsd_enable  =  false
    $knot_enable =  true
    file {'/usr/local/bin/dns-control':
      ensure => link,
      target => '/usr/sbin/knotc',
    }
  }
  # Currently nsd and knot dont support signed 
  # and signed policy so we remove them
  $_zones = $zones.reduce({}) |$reduce_store, $value| {
    $zone = $value[0]
    $config = $value[1].filter |$key| { $key[0] !~ /^signe/ }
    $tmp = merge($reduce_store, {$zone => $config})
    $tmp
  }
  if $master {
    Dns::Tsig <<| tag == "dns::${environment}_${instance}_slave_tsig" |>>
    Dns::Remote <<| tag == "dns::${environment}_${instance}_slave_remote" |>>
    #$_master_zones = $zones.map |String $zone, Dns::Zone $config| {
    #  { $zone =>  { 'provide_xfrs' => ['all slaves'] } }
    #}
  } else {
    $tsigs.each |String $tsig, Hash $config| {
      @@dns::tsig {"dns::export_${instance}_${tsig}":
        algo => pick($config['algo'], 'hmac-sha256'),
        data => $config['data'],
        tag  => "dns::${environment}_${instance}_slave_tsigs",
      }
    }
    @@dns::remote {"dns::export_${instance}_${::fqdn}":
      address4  => $default_ipv4,
      address6  => $default_ipv6,
      tsig_name => $default_tsig_name,
      port      => $port,
    }
  }

  if $ensure == 'present' {
    class { '::nsd':
      enable            => $nsd_enable,
      ip_addresses      => $ip_addresses,
      server_count      => $server_count,
      nsid              => $nsid,
      identity          => $identity,
      default_tsig_name => $default_tsig_name,
      files             => $files,
      tsigs             => $tsigs,
      zones             => $_zones,
      remotes           => $remotes,
    }
    class { '::knot':
      enable            => $knot_enable,
      ip_addresses      => $ip_addresses,
      server_count      => $server_count,
      nsid              => $nsid,
      identity          => $identity,
      default_tsig_name => $default_tsig_name,
      files             => $files,
      tsigs             => $tsigs,
      zones             => $_zones,
      remotes           => $remotes,
    }
  }
  if $enable_nagios {
    $_ip_addresses_list = join($ip_addresses, ' ')

    $zones.each |String $zone, Hash $config| {
      if has_key($config, 'masters') {
        $_masters = flatten($config['masters'].map |String $master| {
          if ! has_key($remotes, $master) {
            fail(
              "Dns::Server[${master}] configured for ${zone} but does not exist"
            )
          }
          delete_undef_values(
            [$remotes[$master]['address4'], $remotes[$master]['address6']]
          )
        })
        if ! empty($_masters) {
          $master_check_args = join($_masters, ' ')
          @@nagios_service{ "${::fqdn}_DNS_ZONE_MASTERS_${zone}":
            ensure              => present,
            use                 => 'generic-service',
            host_name           => $::fqdn,
            service_description => "DNS_ZONE_MASTERS_${zone}",
            check_command       => "check_nrpe_args!check_dns!${zone}!${master_check_args}!${_ip_addresses_list}",
          }
        }
      }
    }
  }
}
