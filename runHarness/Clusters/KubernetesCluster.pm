# Copyright (c) 2017 VMware, Inc. All Rights Reserved.
# 
# Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
# Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
# Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
# INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
# WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
# THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
package KubernetesCluster;

use Moose;
use MooseX::Storage;
use ComputeResources::Cluster;
use VirtualInfrastructures::VirtualInfrastructure;
use WeathervaneTypes;
use Log::Log4perl qw(get_logger);

use namespace::autoclean;

with Storage( 'format' => 'JSON', 'io' => 'File' );

extends 'Cluster';

override 'initialize' => sub {
	my ( $self, $paramHashRef ) = @_;
		
	super();
};

override 'registerService' => sub {
	my ( $self, $serviceRef ) = @_;
	my $console_logger = get_logger("Console");
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	my $servicesRef    = $self->servicesRef;

	my $dockerName = $serviceRef->getDockerName();
	$logger->debug( "Registering service $dockerName with cluster ",
		$self->clusterName );

	if ( $serviceRef->useDocker() ) {
			$console_logger->error( "Service $dockerName running on cluster ",
				$self->clusterName, " should not have useDocker set to true." );
			exit(-1);
	}

	push @$servicesRef, $serviceRef;

};

sub kubernetesDeleteAll {
	my ( $self, $resourceType, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesDelete deleteAll of type $resourceType in namespace $namespace");

	my $kubernetesConfigFile = $self->getParamValue('kubernetesConfigFile');

	my $cmd;
	my $outString;
	$cmd = "KUBECONFIG=$kubernetesConfigFile kubectl delete $resourceType --all --namespace=$namespace 2>&1";
	$outString = `$cmd`;
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	
}

sub kubernetesDeleteAllWithLabel {
	my ( $self, $selector, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesDeleteAllWithLabel with label $selector in namespace $namespace");

	my $kubernetesConfigFile = $self->getParamValue('kubernetesConfigFile');

	my $cmd;
	my $outString;
	$cmd = "KUBECONFIG=$kubernetesConfigFile  kubectl delete all --selector=$selector --namespace=$namespace 2>&1";
	$outString = `$cmd`;
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	$cmd = "KUBECONFIG=$kubernetesConfigFile  kubectl delete configmap --selector=$selector --namespace=$namespace 2>&1";
	$outString = `$cmd`;
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	
}

sub kubernetesDeleteAllWithLabelAndResourceType {
	my ( $self, $selector, $resourceType, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesDeleteAllWithLabelAndResourceType with resourceType $resourceType, label $selector in namespace $namespace");

	my $kubernetesConfigFile = $self->getParamValue('kubernetesConfigFile');

	my $cmd;
	my $outString;
	$cmd = "KUBECONFIG=$kubernetesConfigFile  kubectl delete $resourceType --selector=$selector --namespace=$namespace 2>&1";
	$outString = `$cmd`;
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	
}

sub kubernetesDelete {
	my ( $self, $resourceType, $resourceName, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesDelete delete $resourceName of type $resourceType in namespace $namespace");

	my $kubernetesConfigFile = $self->getParamValue('kubernetesConfigFile');

	my $cmd;
	my $outString;
	$cmd = "KUBECONFIG=$kubernetesConfigFile  kubectl delete $resourceType $resourceName --namespace=$namespace 2>&1";
	$outString = `$cmd`;
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	
}

# Does a kubectl exec in the first pod where the impl label matches  
# serviceImplName.  It does the exec in the container with the same name.
sub kubernetesExecOne {
	my ( $self, $serviceTypeImpl, $commandString, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	my $console_logger = get_logger("Console");
	$logger->debug("kubernetesExecOne exec $commandString for serviceTypeImpl $serviceTypeImpl, namespace $namespace");

	my $kubernetesConfigFile = $self->getParamValue('kubernetesConfigFile');

	# Get the list of pods
	my $cmd;
	my $outString;	
	$cmd = "KUBECONFIG=$kubernetesConfigFile  kubectl get pod -o=jsonpath='{.items[*].metadata.name}' --selector=impl=$serviceTypeImpl --namespace=$namespace 2>&1";
	$outString = `$cmd`;
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	my @names = split /\s+/, $outString;
	if ($#names < 0) {
		$console_logger->error("kubernetesExecOne: There are no pods with label $serviceTypeImpl in namespace $namespace");
		exit(-1);
	}
	
	# Get the name of the first pod
	my $podName = $names[0];
	
	$cmd = "KUBECONFIG=$kubernetesConfigFile  kubectl exec -c $serviceTypeImpl --namespace=$namespace $podName -- $commandString 2>&1";
	$outString = `$cmd`;
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	
	return $outString;
	
}

# Does a kubectl exec in all p[ods] where the impl label matches  
# serviceImplName.  It does the exec in the container with the same name.
sub kubernetesExecAll {
	my ( $self, $serviceTypeImpl, $commandString, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	my $console_logger = get_logger("Console");
	$logger->debug("kubernetesExecAll exec $commandString for serviceTypeImpl $serviceTypeImpl, namespace $namespace");

	my $kubernetesConfigFile = $self->getParamValue('kubernetesConfigFile');

	# Get the list of pods
	my $cmd;
	my $outString;	
	$cmd = "KUBECONFIG=$kubernetesConfigFile  kubectl get pod -o=jsonpath='{.items[*].metadata.name}' --selector=impl=$serviceTypeImpl --namespace=$namespace 2>&1";
	$outString = `$cmd`;
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	my @names = split /\s+/, $outString;
	if ($#names < 0) {
		$console_logger->error("kubernetesExecOne: There are no pods with label $serviceTypeImpl in namespace $namespace");
		exit(-1);
	}
	
	foreach my $podName (@names) { 	
		$cmd = "KUBECONFIG=$kubernetesConfigFile  kubectl exec -c $serviceTypeImpl --namespace=$namespace $podName -- $commandString 2>&1";
		$outString = `$cmd`;
		$logger->debug("Command: $cmd");
		$logger->debug("Output: $outString");
	}
}

sub kubernetesApply {
	my ( $self, $fileName, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesApply apply file $fileName in namespace $namespace");

	my $kubernetesConfigFile = $self->getParamValue('kubernetesConfigFile');

	my $cmd;
	my $outString;
	$cmd = "KUBECONFIG=$kubernetesConfigFile  kubectl apply -f $fileName --namespace=$namespace 2>&1";
	$outString = `$cmd`;
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
}

sub kubernetesCreateSecret {
	my ( $self, $keyFileName, $certFileName, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesCreateSecret  keyFile $keyFileName, certFile $certFileName, in namespace $namespace");

	my $kubernetesConfigFile = $self->getParamValue('kubernetesConfigFile');

	my $cmd;
	my $outString;
	$cmd = "KUBECONFIG=$kubernetesConfigFile kubectl create secret tls tls-secret --key $keyFileName --cert $certFileName --namespace=$namespace 2>&1";
	$outString = `$cmd`;
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
}

sub kubernetesGetIngressIp {
	my ( $self, $labelString, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesAreAllPodRunning LabelString $labelString, namespace $namespace");

	my $kubernetesConfigFile = $self->getParamValue('kubernetesConfigFile');

	my $cmd;
	my $outString;
	$cmd = "KUBECONFIG=$kubernetesConfigFile  kubectl get ingress --selector=$labelString -o=jsonpath='{.items[*].status.loadBalancer.ingress[0].ip}' --namespace=$namespace 2>&1";
	$outString = `$cmd`;
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	
	my @ips = split /\n/, $outString;
	if ($#ips < 0) {
		$logger->debug("kubernetesGetIngressIp: There are no ingresses with label $labelString in namespace $namespace");
		return 0;
	}
	
	return $ips[0];
}

sub kubernetesIngressHasIp {
	my ( $self, $labelString, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesAreAllPodRunning LabelString $labelString, namespace $namespace");

	my $kubernetesConfigFile = $self->getParamValue('kubernetesConfigFile');

	my $cmd;
	my $outString;
	$cmd = "KUBECONFIG=$kubernetesConfigFile  kubectl get ingress --selector=$labelString -o=jsonpath='{.items[*].status.loadBalancer.ingress[0].ip}' --namespace=$namespace 2>&1";
	$outString = `$cmd`;
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	
	my @ips = split /\n/, $outString;
	if ($#ips < 0) {
		$logger->debug("kubernetesGetIngressIp: There are no ingresses with label $labelString in namespace $namespace");
		return 0;
	}
	
	if (!$ips[0]) {
		return 0;
	} else {
		return 1;
	}
}

sub kubernetesGetNodePortForPortNumber {
	my ( $self, $labelString, $portNumber, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesGetNodePortForPortNumber LabelString $labelString, port $portNumber, namespace $namespace");

	my $kubernetesConfigFile = $self->getParamValue('kubernetesConfigFile');

	my $cmd;
	my $outString;
	$cmd = "KUBECONFIG=$kubernetesConfigFile  kubectl get service --selector=$labelString -o=jsonpath='{range .items[*]}{.spec.ports[*].port}{\",\"}{.spec.ports[*].nodePort}{\"\\n\"}{end}' --namespace=$namespace 2>&1";
	$outString = `$cmd`;
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	
	my @lines = split /\n/, $outString;
	if ($#lines < 0) {
		$logger->error("kubernetesGetNodePortForPortNumber: There are no services with label $labelString in namespace $namespace");
		return "";
	}
	
	my $line = $lines[0];
	my @portLists = split /,/, $line;
	if ($#portLists < 1) {
		$logger->error("kubernetesGetNodePortForPortNumber: There are no nodePorts on services with label $labelString in namespace $namespace");
		return "";
	}

	my @ports = split /\s+/, $portLists[0];
	my @nodePorts = split /\s+/, $portLists[1];
	if ($#ports != $#nodePorts) {
		$logger->error("kubernetesGetNodePortForPortNumber: There are not nodePorts for every port on the services with label $labelString in namespace $namespace");
		return "";
	}
	
	my $index = 0;
	foreach 	my $port (@ports) {
		if ($port == $portNumber) {
			return $nodePorts[$index];
		}
		$index++;
	}

	$logger->error("kubernetesGetNodePortForPortNumber: There is no port $portNumber on the services with label $labelString in namespace $namespace");
	return "";
		
}

sub kubernetesAreAllPodRunning {
	my ( $self, $podLabelString, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesAreAllPodRunning podLabelString $podLabelString, namespace $namespace");

	my $kubernetesConfigFile = $self->getParamValue('kubernetesConfigFile');

	my $cmd;
	my $outString;
	$cmd = "KUBECONFIG=$kubernetesConfigFile  kubectl get pod --selector=$podLabelString -o=jsonpath='{.items[*].status.phase}' --namespace=$namespace 2>&1";
	$outString = `$cmd`;
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");

	my @stati = split /\s+/, $outString;
	if ($#stati < 0) {
		$logger->debug("kubernetesAreAllPodRunning: There are no pods with label $podLabelString in namespace $namespace");
		return 0;
	}
	
	foreach my $status (@stati) { 
		if ($status ne "Running") {
			$logger->debug("kubernetesAreAllPodRunning: Found a non-running pod: $status");
			return 0;
		}	
	}
	$logger->debug("kubernetesAreAllPodRunning: All pods are running");
	return 1;
}

sub kubernetesDoPodsExist {
	my ( $self, $podLabelString, $namespace ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	$logger->debug("kubernetesAreAllPodRunning podLabelString $podLabelString, namespace $namespace");

	my $kubernetesConfigFile = $self->getParamValue('kubernetesConfigFile');

	my $cmd;
	my $outString;
	$cmd = "KUBECONFIG=$kubernetesConfigFile  kubectl get pod --selector=$podLabelString -o=jsonpath='{.items[*].status.phase}' --namespace=$namespace 2>&1";
	$outString = `$cmd`;
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");

	my @stati = split /\s+/, $outString;
	if ($#stati < 0) {
		$logger->debug("kubernetesDoPodsExist: There are no pods with label $podLabelString in namespace $namespace");
		return 0;
	}

	return 1;
}

sub kubernetesGetLogs {
	my ( $self, $podLabelString, $serviceTypeImpl, $namespace, $destinationPath ) = @_;
	my $logger         = get_logger("Weathervane::Clusters::KubernetesCluster");
	my $console_logger = get_logger("Console");
	$logger->debug("kubernetesGetLogs podLabelString $podLabelString, namespace $namespace");
	
	my $kubernetesConfigFile = $self->getParamValue('kubernetesConfigFile');

	# Get the list of pods
	my $cmd;
	my $outString;	
	$cmd = "KUBECONFIG=$kubernetesConfigFile  kubectl get pod -o=jsonpath='{.items[*].metadata.name}' --selector=impl=$serviceTypeImpl --namespace=$namespace 2>&1";
	$outString = `$cmd`;
	$logger->debug("Command: $cmd");
	$logger->debug("Output: $outString");
	my @names = split /\s+/, $outString;
	if ($#names < 0) {
		$console_logger->error("kubernetesGetLogs: There are no pods with label $serviceTypeImpl in namespace $namespace");
		exit(-1);
	}
	
	foreach my $podName (@names) { 	
		$cmd = "KUBECONFIG=$kubernetesConfigFile  kubectl logs -c $serviceTypeImpl --namespace=$namespace $podName 2>&1";
		$outString = `$cmd`;

		$logger->debug("Command: $cmd");
		my $logName          = "$destinationPath/${podName}.log";
		my $applog;
		open( $applog, ">$logName" )
	  	||	 die "Error opening $logName:$!";
	  			
		print $applog $outString;
	
		close $applog;

	}
	
	return 0;
}

__PACKAGE__->meta->make_immutable;

1;
