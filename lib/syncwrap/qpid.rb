#--
# Copyright (c) 2011-2013 David Kellum
#
# Licensed under the Apache License, Version 2.0 (the "License"); you
# may not use this file except in compliance with the License.  You may
# obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.  See the License for the specific language governing
# permissions and limitations under the License.
#++

require 'syncwrap/common'
require 'syncwrap/distro'

# Qpid AMQP broker provisioning. Currently this is RHEL/AmazonLinux
# centric.
module SyncWrap::Qpid
  include SyncWrap::Common
  include SyncWrap::Distro

  attr_accessor :qpid_src_root

  attr_accessor :qpid_version
  attr_accessor :qpid_repo
  attr_accessor :qpid_distro

  attr_accessor :corosync_version
  attr_accessor :corosync_repo

  def initialize
    super

    @qpid_src_root = '/tmp/src'

    @qpid_version = '0.18'
    @qpid_repo = 'http://apache.osuosl.org/qpid'
    @qpid_distro = 'amzn1'

    @corosync_version = '1.4.4'
    @corosync_repo = 'https://github.com/downloads/corosync/corosync'
  end

  def qpid_install
    unless exist?( "/usr/local/sbin/qpidd" )
      qpid_install!
      qpid_install_init!
    end
    qpid_tools_install
    rput( 'usr/local/etc/qpidd.conf', :user => 'root' )
  end

  def qpid_install_init!
    unless exec_conditional { run "id qpidd >/dev/null" } == 0
      sudo <<-SH
        useradd -r qpidd
        mkdir -p /var/local/qpidd
        chown qpidd:qpidd /var/local/qpidd
      SH
    end

    rput( 'etc/init.d/qpidd', :user => 'root' )

    # Add to init.d
    dist_install_init_service( 'qpidd' )
  end

  def qpid_tools_install
    unless exist?( "/usr/bin/qpid-config" )
      qpid_tools_install!
    end
  end

  def qpid_install!
    corosync_install!( :devel => true )
    qpid_build
  end

  def qpid_tools_install!
    dist_install( 'python-setuptools' )
    qpid_src = "#{qpid_src_root}/qpid-#{qpid_version}"

    run <<-SH
      mkdir -p #{qpid_src_root}
      rm -rf #{qpid_src}
      cd #{qpid_src_root}
      curl -sSL #{qpid_tools_tarball} | tar -zxf -
    SH

    sudo <<-SH
      cd #{qpid_src}
      easy_install ./python ./tools ./extras/qmf
    SH
  end

  def qpid_build
    qpid_install_build_deps
    qpid_install_deps

    qpid_src = "#{qpid_src_root}/qpidc-#{qpid_version}"

    run <<-SH
      mkdir -p #{qpid_src_root}
      rm -rf #{qpid_src}
      cd #{qpid_src_root}
      curl -sSL #{qpid_src_tarball} | tar -zxf -
      cd #{qpid_src}
      ./configure > /dev/null
      make > /dev/null
    SH

    sudo <<-SH
      cd #{qpid_src}
      make install > /dev/null
    SH

    run <<-SH
      cd #{qpid_src}
      make check > /dev/null
    SH

    sudo <<-SH
      cd /usr/local
      rm -f /tmp/qpidc-#{qpid_version}-1-#{qpid_distro}-x64.tar.gz
      tar -zc \
           --exclude games --exclude lib64/perl5 --exclude src \
           --exclude share/man --exclude share/perl5 --exclude share/info \
           --exclude share/applications \
           -f /tmp/qpidc-#{qpid_version}-1-#{qpid_distro}-x64.tar.gz .
    SH
  end

  def qpid_src_tarball
    "#{qpid_repo}/#{qpid_version}/qpid-cpp-#{qpid_version}.tar.gz"
  end

  def qpid_tools_tarball
    "#{qpid_repo}/#{qpid_version}/qpid-#{qpid_version}.tar.gz"
  end

  def qpid_install_build_deps
    dist_install( %w[ gcc gcc-c++ make autogen autoconf
                      help2man libtool pkgconfig rpm-build ] )
  end

  def qpid_install_deps
    dist_install( %w[ nss-devel boost-devel libuuid-devel swig
                      ruby-devel python-devel cyrus-sasl-devel ] )
  end

  def corosync_install( opts = {} )
    unless exist?( "/usr/sbin/corosync" )
      corosync_install!( opts )
    end
  end

  def corosync_install!( opts = {} )
    corosync_build
    dist_install( "#{corosync_src}/x86_64/*.rpm", :succeed => true )
  end

  def corosync_build
    qpid_install_build_deps
    corosync_install_build_deps

    run <<-SH
      mkdir -p #{qpid_src_root}
      rm -rf #{corosync_src}
      cd #{qpid_src_root}
      curl -sSL #{corosync_repo}/corosync-#{corosync_version}.tar.gz | tar -zxf -
      cd #{corosync_src}
      ./autogen.sh
      ./configure > /dev/null
      make rpm > /dev/null
    SH

  end

  def corosync_packages( include_devel = false )
    packs = [ "corosync-#{corosync_version}-1.#{qpid_distro}.x86_64.rpm",
              "corosynclib-#{corosync_version}-1.#{qpid_distro}.x86_64.rpm" ]
    packs <<  "corosynclib-devel-#{corosync_version}-1.#{qpid_distro}.x86_64.rpm" if include_devel
    packs
  end

  def corosync_install_build_deps
    dist_install( %w[ nss-devel libibverbs-devel librdmacm-devel ] )
  end

  def corosync_src
    "#{qpid_src_root}/corosync-#{corosync_version}"
  end

  # Simplify qpid install by using pre-built binaries (for example,
  # archived from the build steps above.)
  module BinRepo
    include SyncWrap::Qpid

    attr_accessor :qpid_prebuild_repo

    def initialize
      super

      @qpid_prebuild_repo = nil
    end

    def qpid_install
      corosync_install
      super
    end

    def qpid_install!
      raise "qpid_prebuild_repo required, but not set" unless qpid_prebuild_repo

      dist_install( %w[ boost cyrus-sasl ] )

      sudo <<-SH
        cd /usr/local
        curl -sS #{qpid_prebuild_repo}/qpidc-#{qpid_version}-1-#{qpid_distro}-x64.tar.gz | tar -zxf -
      SH
    end

    def corosync_install!( opts = {} )
      raise "qpid_prebuild_repo required, but not set" unless qpid_prebuild_repo
      packs = corosync_packages
      curls = packs.map do |p|
        "curl -sS -O #{qpid_prebuild_repo}/#{p}"
      end

      sudo <<-SH
        rm -rf /tmp/rpm-drop
        mkdir -p /tmp/rpm-drop
        cd /tmp/rpm-drop
        #{curls.join("\n")}
      SH
      dist_install( "/tmp/rpm-drop/*.rpm", :succeed => true )
    end

    # Where uploaded qpid-python-tools-M.N.tar.gz contains the
    # ./python ./tools ./extras/qmf packages for easy_install.
    def qpid_tools_tarball
      "#{qpid_prebuild_repo}/qpid-python-tools-#{qpid_version}.tar.gz"
    end

  end

end
