package App::AccessLog2ElasticsearchTest;
use parent qw(Test::Class);

use strict;
use warnings;

use Test::More;
use Path::Class::File;

sub startup : Test(startup => 1) {
	my ($self) = @_;

	use_ok('App::AccessLog2Elasticsearch');
}

sub new_test : Test(1) {
	my ($self) = @_;

	new_ok('App::AccessLog2Elasticsearch' => [{
		log   => Path::Class::File->new(qw(t testdata access.log)),
		vhost => 'example.com',
	}]);
}

1;
