# Copyright 2017-2019 VMware, Inc.
# SPDX-License-Identifier: BSD-2-Clause
package AuctionBidKubernetesService;

use Moose;
use MooseX::Storage;

use POSIX;
use Services::KubernetesService;
use Parameters qw(getParamValue);
use StatsParsers::ParseGC qw( parseGCLog );
use Log::Log4perl qw(get_logger);

use namespace::autoclean;

with Storage( 'format' => 'JSON', 'io' => 'File' );

extends 'KubernetesService';

override 'initialize' => sub {
	my ($self) = @_;

	super();
};

sub configure {
	my ( $self, $dblog, $serviceType, $users ) = @_;
	my $logger = get_logger("Weathervane::Services::AuctionBidKubernetesService");
	$logger->debug("Configure AuctionBidService kubernetes");
	print $dblog "Configure AuctionBidService Kubernetes\n";

	my $namespace = $self->namespace;	
	my $configDir        = $self->getParamValue('configDir');

	my $serviceParamsHashRef =
	  $self->appInstance->getServiceConfigParameters( $self, $self->getParamValue('serviceType') );

	my $threads            = $self->getParamValue('auctionBidServerThreads');
	my $connections        = $self->getParamValue('auctionBidServerJdbcConnections');
	my $tomcatCatalinaBase = $self->getParamValue('bidServiceCatalinaBase');
	my $maxIdle = ceil($self->getParamValue('auctionBidServerJdbcConnections') / 2);
	my $nodeNum = $self->instanceNum;
	my $maxConnections =
	  ceil( $self->getParamValue('frontendConnectionMultiplier') *
		  $users /
		  ( $self->appInstance->getTotalNumOfServiceType('auctionBidServer') * 1.0 ) );
	if ( $maxConnections < 100 ) {
		$maxConnections = 100;
	}

	my $completeJVMOpts .= $self->getParamValue('auctionBidServerJvmOpts');
	$completeJVMOpts .= " " . $serviceParamsHashRef->{"jvmOpts"};

	if ( $self->getParamValue('logLevel') >= 3 ) {
		$completeJVMOpts .= " -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -Xloggc:$tomcatCatalinaBase/logs/gc.log ";
	}
	if ( $self->getParamValue('enableJmx') ) {
		$completeJVMOpts .= " -Dcom.sun.management.jmxremote.rmi.port=9090 -Dcom.sun.management.jmxremote=true "
							. "-Dcom.sun.management.jmxremote.port=9090 -Dcom.sun.management.jmxremote.ssl=false "
							. "-Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.local.only=false "
							. "-Djava.rmi.server.hostname=127.0.0.1 ";
	}
	$completeJVMOpts .= " -DnodeNumber=$nodeNum ";
	$completeJVMOpts .= " -DnodeNumber=$nodeNum ";
	
	my $numAuctionBidServers = $self->appInstance->getTotalNumOfServiceType('auctionBidServer');

	open( FILEIN,  "$configDir/kubernetes/auctionbidservice.yaml" ) or die "$configDir/kubernetes/auctionbidservice.yaml: $!\n";
	open( FILEOUT, ">/tmp/auctionbidservice-$namespace.yaml" )             or die "Can't open file /tmp/auctionbidservice-$namespace.yaml: $!\n";
	
	while ( my $inline = <FILEIN> ) {

		if ( $inline =~ /TOMCAT_JVMOPTS:/ ) {
			print FILEOUT "  TOMCAT_JVMOPTS: \"$completeJVMOpts\"\n";
		}
		elsif ( $inline =~ /TOMCAT_THREADS:/ ) {
			print FILEOUT "  TOMCAT_THREADS: \"$threads\"\n";
		}
		elsif ( $inline =~ /TOMCAT_JDBC_CONNECTIONS:/ ) {
			print FILEOUT "  TOMCAT_JDBC_CONNECTIONS: \"$connections\"\n";
		}
		elsif ( $inline =~ /TOMCAT_JDBC_MAXIDLE:/ ) {
			print FILEOUT "  TOMCAT_JDBC_MAXIDLE: \"$maxIdle\"\n";
		}
		elsif ( $inline =~ /TOMCAT_CONNECTIONS:/ ) {
			print FILEOUT "  TOMCAT_CONNECTIONS: \"$maxConnections\"\n";
		}
		elsif ( $inline =~ /replicas:/ ) {
			print FILEOUT "  replicas: $numAuctionBidServers\n";
		}
		elsif ( $inline =~ /(\s+)resources/ )  {
			my $indent = $1;
			if ($self->getParamValue('useKubernetesRequests') || $self->getParamValue('useKubernetesLimits')) {
				print FILEOUT $inline;
			}
			if ($self->getParamValue('useKubernetesRequests') || $self->getParamValue('useKubernetesLimits')) {
				print FILEOUT "$indent  requests:\n";
				print FILEOUT "$indent    cpu: " . $self->getParamValue('auctionBidServerCpus') . "\n";
				print FILEOUT "$indent    memory: " . $self->getParamValue('auctionBidServerMem') . "\n";
			}
			if ($self->getParamValue('useKubernetesLimits')) {
				print FILEOUT "$indent  limits:\n";
				print FILEOUT "$indent    cpu: " . $self->getParamValue('auctionBidServerCpus') . "\n";
				print FILEOUT "$indent    memory: " . $self->getParamValue('auctionBidServerMem') . "\n";						
			}
			
			do {
				$inline = <FILEIN>;
			} while(!($inline =~ /readinessProbe/));
			print FILEOUT $inline;			
		}
		elsif ( $inline =~ /(\s+)initialDelaySeconds:/ ) {
	        # Randomize the initialDelaySeconds on the readiness probes
			my $indent = $1;
			my $delay = int(rand(60)) + 1;
			print FILEOUT "${indent}initialDelaySeconds: $delay\n";
		}
		elsif ( $inline =~ /(\s+)imagePullPolicy/ ) {
			print FILEOUT "${1}imagePullPolicy: " . $self->appInstance->imagePullPolicy . "\n";
		}
		elsif ( $inline =~ /(\s+\-\simage:\s)(.*\/)(.*\:)/ ) {
			my $version  = $self->host->getParamValue('dockerWeathervaneVersion');
			my $dockerNamespace = $self->host->getParamValue('dockerNamespace');
			print FILEOUT "${1}$dockerNamespace/${3}$version\n";
		}
		elsif ( $inline =~ /^(\s+)requiredDuringScheduling/ ) {
			my $indent = $1;
			print FILEOUT $inline;
			do {
				$inline = <FILEIN>;
				print FILEOUT $inline;			
			} while(!($inline =~ /matchExpressions/));
			if ($self->getParamValue('instanceNodeLabels')) {
				my $workloadNum    = $self->appInstance->workload->instanceNum;
				my $appInstanceNum = $self->appInstance->instanceNum;
           	    print FILEOUT "${indent}    - key: wvauctionw${workloadNum}i${appInstanceNum}\n";
           	    print FILEOUT "${indent}      operator: Exists\n";
			}
		}
		else {
			print FILEOUT $inline;
		}

	}
	
	close FILEIN;
	close FILEOUT;

}

override 'isUp' => sub {
	my ($self, $fileout) = @_;
	my $cluster = $self->host;
	my $numServers = $self->appInstance->getTotalNumOfServiceType($self->getParamValue('serviceType'));
	if ($cluster->kubernetesAreAllPodUpWithNum ($self->getImpl(), "curl -s http://localhost:8080/auction/healthCheck", $self->namespace, 'alive', $numServers)) { 
		return 1;
	}
	return 0;
};

override 'stopStatsCollection' => sub {
	my ($self) = @_;
	my $logger = get_logger("Weathervane::Services::AuctionBidKubernetesService");
	$logger->debug("stopStatsCollection");
};

override 'startStatsCollection' => sub {
	my ( $self, $intervalLengthSec, $numIntervals ) = @_;
	my $hostname         = $self->host->name;
	my $logger = get_logger("Weathervane::Services::AuctionBidKubernetesService");
	$logger->debug("startStatsCollection hostname = $hostname");

};

override 'getStatsFiles' => sub {
	my ( $self, $destinationPath ) = @_;
	my $logger = get_logger("Weathervane::Services::AuctionBidKubernetesService");
	$logger->debug("getStatsFiles");

};

sub cleanLogFiles {
	my ( $self, $destinationPath ) = @_;
	my $logger = get_logger("Weathervane::Services::AuctionBidKubernetesService");
	$logger->debug("cleanLogFiles");
}

sub parseLogFiles {
	my ($self) = @_;

}

sub getConfigFiles {
	my ( $self, $destinationPath ) = @_;
	my $namespace = $self->namespace;
	`mkdir -p $destinationPath`;

	`cp /tmp/auctionbidservice-$namespace.yaml $destinationPath/. 2>&1`;

}

sub getConfigSummary {
	my ($self) = @_;
	tie( my %csv, 'Tie::IxHash' );
	$csv{"auctionBidServiceThreads"}     = $self->getParamValue('auctionBidServerThreads');
	$csv{"auctionBidServiceConnections"} = $self->getParamValue('auctionBidServerJdbcConnections');
	$csv{"auctionBidServiceJvmOpts"}     = $self->getParamValue('auctionBidServerJvmOpts');
	return \%csv;
}

sub getStatsSummary {
	my ( $self, $statsLogPath, $users ) = @_;
	tie( my %csv, 'Tie::IxHash' );

	return \%csv;
}

__PACKAGE__->meta->make_immutable;

1;
