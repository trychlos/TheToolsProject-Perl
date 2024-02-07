Toops, a perl-port of Tools

Toops for Windows:
- install Strawberry Perl 5.36 in C:\Strawberry
	5.36 is the last version managed by Win32::SqlServer provided binaries - so stay stuck to this version unless you are willing to install from sources
- install additionnal modules
	> Win32::SqlServer https://www.sommarskog.se/MSSQL/index.html
- set the HOST_ENV value of your machine
- install and configure Toops for your site:
	> set the PERL5LIB global environment variable to address the Toops directory
	> set a TTP_SITE global environment variable to address the directory which contains your site configuration
	> (optional) set a TTP_ROOT global environment variable in PATH-style like to address several Toops trees
	> update the PATH to address all your Toops/bin directories
	> install CPAN packages
	  Data::UUID
	  Net::MQTT::Simple
	  Proc::Background

Site configuration:
Install in TTP_SITE/:
- a copy of TOOPS_ROOT/Mods/etc/toops.json.default as TTP_SITE/toops.json
- update it according your needs and preferences

Host configuration:
Install in TTP_SITE/ as <hostname>.json:
- describe your services
  A service is characterized by the fact that we want describe in this configuration file the difference for *this* service between several environments
  e.g. TOM59 service is referenced in DEV and in PROD/

Windows Note:
	We do not know at the moment how to ssh into a remote host to exec a remote script.
	We so get stuck in our machine.

TTPVars:
	config
		site					the computed site configuration after variables interpretation
			toops
				logsDir
			site
				rootDir
		<hostname>
			Services
			DBMSInstances
			...
			name: <hostname>
	run
		exitCode
		help
		verbose
		logsDir
		logsMain
		
		# when run as a command.pl verb
		command
			path
			args
			basename
			directory
			name
			verbsDir
			started
		verb
			name
			args
			path
		<command>
			instance
				name
				data: $hostConfig->{DBMSInstances}{$instance}
			name
		
		# when run by a daemon
		daemon

# when writing and using new commands or verbs
# --------------------------------------------
For debugging purposes workload.cmd may take additional arguments, sayf or example -dummy, -verbose, -nocolored
As these additional arguments will be passed to each and every executed TTP command/verb, all these must at least *support* (if not honor) these standard arguments.

TODO
    1 24- 1-29 Toops::getOptions doesn't work as we do not know how to pass arguments to GetOptions()

Topics tree
  published
	<emitter_host> / executionReport / <command> / <verb>
  retained
	<emitter_host> / daemon / <daemon_name> / status				where daemon_name is the base name of the json file, without the extension
