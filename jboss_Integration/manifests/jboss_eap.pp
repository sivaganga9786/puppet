class jboss_integration::jboss_eap {
  $jboss_user               = 'jboss'
  $jboss_group              = 'jboss'
  $jboss_version            = '8.0.0'
  $jboss_home               = '/opt/jboss/EAP8'
  $jboss_install_dir        = $jboss_home
  $jboss_maven_repo_dir     = '/opt/jboss/maven_dep'
  $jboss_installer_manager_dir = '/opt/jboss/IM'
  $jboss_installer_archive  = "/tmp/jboss-eap-${jboss_version}-installation-manager.zip"
  $jboss_maven_repo_archive = "/tmp/jboss_eap_${jboss_version}_maven_repository.zip"
  $fqdn_name                = $facts['networking']['fqdn']
  $host_part                = $fqdn_name.split('.')[0]
  $std_name                 = "${host_part}_default"
  $jboss_user_name          = 'jbossadmin'
  $jboss_password           = 'password1!'
  $jboss_logpath            = '/var/jboss/EAP8/Logs'
  $keystore_source          = '/opt/jboss/server.keystore.jks'
  $truststore_source        = '/opt/jboss/server.truststore.jks'
  $keystore_dest            = "${jboss_home}/standalone/configuration/server.keystore.jks"
  $truststore_dest          = "${jboss_home}/standalone/configuration/server.truststore.jks"

  package { ['java-17-openjdk', 'unzip', 'wget']:
    ensure => installed,
  }

  exec { 'extract_jboss_installer':
    command => "unzip -o ${jboss_installer_archive} -d ${jboss_installer_manager_dir}",
    creates => $jboss_installer_manager_dir,
    user    => $jboss_user,
    group   => $jboss_group,
    require => Package['unzip'],
  }

  exec { 'extract_jboss_maven_repo':
    command => "unzip -o ${jboss_maven_repo_archive} -d ${jboss_maven_repo_dir}",
    creates => $jboss_maven_repo_dir,
    user    => $jboss_user,
    group   => $jboss_group,
    require => Package['unzip'],
  }

  exec { 'jboss_installer_manager':
    command => "${jboss_installer_manager_dir}/bin/jboss-eap-installation-manager.sh install --profile eap-8.0 --dir ${jboss_install_dir} --repositories=file:${jboss_maven_repo_dir}/maven-repository --accept-license-agreements",
    creates => $jboss_home,
    user    => $jboss_user,
    group   => $jboss_group,
    path    => ['/bin', '/usr/bin'],
    require => [Exec['extract_jboss_installer'], Exec['extract_jboss_maven_repo']],
  }

  exec { 'add_jboss_user':
    command => "${jboss_install_dir}/bin/add-user.sh -u ${jboss_user_name} -p ${jboss_password}",
    creates => "${jboss_install_dir}/standalone/configuration/mgmt-users.properties",
    path    => ['/bin', '/usr/bin'],
    require => Exec['jboss_installer_manager'],
  }

  # file_line { 'set_java_home_in_add_user':
  #   path    => "${jboss_install_dir}/bin/add-user.sh",
  #   line    => 'export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64',
  #   match   => '^export JAVA_HOME=',
  #   require => Exec['add_jboss_user'],
  # }

  # file_line { 'set_path_in_add_user':
  #   path    => "${jboss_install_dir}/bin/add-user.sh",
  #   line    => 'export PATH=$JAVA_HOME/bin:$PATH',
  #   match   => '^export PATH=\$JAVA_HOME/bin',
  #   require => Exec['add_jboss_user'],
  # }

  [
    "${jboss_home}/standalone/configuration/standalone.xml",
    "${jboss_home}/bin/jboss-cli.sh",
    "${jboss_home}/bin/standalone.conf",
  ].each |$path| {
    $filename = $path.split('/').last
    if $filename =~ /^jboss-cli\.sh$/ {
      $mode = '0755'
    } else {
      $mode = '0644'
    }

    file { $path:
      ensure  => file,
      content => epp("psre_integration/${filename}.epp"),
      owner   => $jboss_user,
      group   => $jboss_group,
      mode    => $mode,
      require => Exec['jboss_installer_manager'],
    }
  }

  file { $keystore_dest:
    ensure  => file,
    source  => "file://${keystore_source}",
    owner   => $jboss_user,
    group   => $jboss_group,
    mode    => '0644',
    require => Exec['jboss_installer_manager'],
  }

  file { $truststore_dest:
    ensure  => file,
    source  => "file://${truststore_source}",
    owner   => $jboss_user,
    group   => $jboss_group,
    mode    => '0644',
    require => Exec['jboss_installer_manager'],
  }

  exec { 'start_jboss':
    command     => "nohup ${jboss_home}/bin/standalone.sh --server-config=standalone.xml -Djboss.server.base.dir=${jboss_home}/standalone -b ${fqdn_name} -bmanagement ${fqdn_name} &",
    user        => $jboss_user,
    environment => ["JBOSS_HOME=${jboss_home}"],
    cwd         => "${jboss_home}/bin",
    path        => ['/bin', '/usr/bin', '/usr/local/bin'],
    unless      => "pgrep -f 'jboss.*standalone' > /dev/null",
    require     => File["${jboss_home}/standalone/configuration/standalone.xml"],
  }
}

