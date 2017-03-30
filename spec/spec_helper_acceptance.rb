# frozen_string_literal: true

require 'beaker-rspec'
require 'beaker/testmode_switcher/dsl'
require 'beaker-pe'
require 'progressbar'

modules = [
  'puppetlabs-stdlib',
  'puppetlabs-concat',
  'stankevich-python',
  'icann-tea'
]
git_repos = [
  {
    mod: 'nsd',
    branch: 'refactor_zone',
    repo: 'https://github.com/icann-dns/puppet-nsd'
  },
  {
    mod: 'knot',
    branch: 'refactor_zone',
    repo: 'https://github.com/icann-dns/puppet-knot'
  }
]
def install_modules(host, modules, git_repos)
  module_root = File.expand_path(File.join(File.dirname(__FILE__), '..'))
  install_dev_puppet_module_on(host, source: module_root)
  modules.each do |m|
    on(host, puppet('module', 'install', m))
  end
  git_repos.each do |g|
    step "Installing puppet module \'#{g[:repo]}\' from git on #{host} to #{default['distmoduledir']}"
    on(host, "git clone -b #{g[:branch]} --single-branch #{g[:repo]} #{default['distmoduledir']}/#{g[:mod]}")
  end
end
# Install Puppet on all hosts
hosts.each do |host|
  step "install packages on #{host}"
  host.install_package('git')
  if host['platform'] =~ %r{freebsd}
    # default installs incorect version
    host.install_package('sysutils/puppet4')
    host.install_package('dns/bind-tools')
  else
    host.install_package('vim')
    host.install_package('dnsutils')
  end
  # remove search list and domain from resolve.conf
  on(host, 'echo $(grep nameserver /etc/resolv.conf) > /etc/resolv.conf')
end
if ENV['BEAKER_TESTMODE'] == 'agent'
  step 'install puppet enterprise'
  _install_pe = fork do
    install_pe
  end
  progress = fork do
    loop do
      step 'Still installing puppet enterprise'
      sleep 60
    end
  end
  Process.wait(_install_pe)
  Process.kill(15, progress)
  master = only_host_with_role(hosts, 'master')
  install_modules(master, modules, git_repos)
else
  step 'install masterless'
  hosts.each do |host|
    install_puppet_on(
      host,
      version: '4',
      puppet_agent_version: '1.6.1',
      default_action: 'gem_install'
    )
    install_modules(host, modules, git_repos)
  end
end
RSpec.configure do |c|
  c.formatter = :documentation
  # c.before :suite do
  #   hosts.each do |host|
  #   end
  # end
end
