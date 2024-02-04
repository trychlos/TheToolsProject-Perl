# Copyright (@) 2023-2024 PWI Consulting

package Mods::Constants;

use strict;
use warnings;

use Sub::Exporter;

Sub::Exporter::setup_exporter({
	exports => [ qw(
		true
		false
		EOL

		EMERG
		ALERT
		CRIT
		ERR
		WARN
		NOTICE
		INFO
		DEBUG
	)]
});

use constant {
	true => 1,
	false => 0,
	EOL => "\n",
	
	EMERG => 'EMERGENCY',
	ALERT => 'ALERT',
	CRIT => 'CRITICAL',
	ERR => 'ERROR',
	WARN => 'WARNING',
	NOTICE => 'NOTICE',
	INFO => 'INFO',
	DEBUG => 'DEBUG'
};

1;
