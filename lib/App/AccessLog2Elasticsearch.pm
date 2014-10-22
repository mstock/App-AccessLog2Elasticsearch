package App::AccessLog2Elasticsearch;

# ABSTRACT: Parse an Apache access log file and create an Elasticsearch document per line

use strict;
use warnings;

use Moose;
use Search::Elasticsearch;
use Apache::Log::Parser;
use MooseX::Types::Path::Class;
use DateTime::Format::Strptime;
use MooseX::FollowPBP;
use Scalar::Util qw(looks_like_number);

with 'MooseX::Getopt';


=head1 SYNOPSIS

	use App::AccessLog2ElasticSearch;

	App::AccessLog2ElasticSearch->new_with_options()->run();

=head1 DESCRIPTION

App::AccessLog2ElasticSearch parses an access log file using
L<Apache::Log::Parser|Apache::Log::Parser> and injects it into Elasticsearch,
with one document per log line.

=head1 METHODS

=head2 new

Constructor, creates new instance of this application.

=head3 Parameters

This method expects its parameters as a hash reference.

=over

=item host

Hostname, IP-address or another identifier of the host the logfile is from.

=item vhost

Virtual host the log file belongs to. Required.

=item log

Path to the log file. Required.

=item index

Elasticsearch index where the documents should be stored. Defaults to C<logs>.

=item type

The type that should be assigned to the documents. Defaults to C<access_log_entry>

=item nodes

Nodes that should be used to access Elasticsearch. Defaults to C<localhost:9200>.

=item es

A L<Search::Elasticsearch::Role::Client::Direct|Search::Elasticsearch::Role::Client::Direct>
instance.

=item date_parser

L<DateTime::Format::Strptime|DateTime::Format::Strptime>-based Parser for the
dates in the log file.

=item log_parser

L<Apache::Log::Parser|Apache::Log::Parser> instance to use for log parsing.

=back

=cut

has 'host' => (
	is            => 'ro',
	isa           => 'Str',
	required      => 0,
	documentation => 'Hostname, IP address or another identifier of the host the logfile is from',
);

has 'vhost' => (
	is            => 'ro',
	isa           => 'Str',
	required      => 1,
	documentation => 'Virtual host the log file belongs to.'
);

has 'log' => (
	is            => 'ro',
	isa           => 'Path::Class::File',
	coerce        => 1,
	required      => 1,
	documentation => 'Path to the log file.',
);

has 'index' => (
	is            => 'ro',
	isa           => 'Str',
	default       => 'logs',
	documentation => 'Name of the index that should be used. Defaults to <logs>.',
);

has 'type' => (
	is            => 'ro',
	isa           => 'Str',
	default       => 'access_log_entry',
	documentation => 'Type to use for the documents. Defaults to <access_log_entry>.',
);

has 'nodes' => (
	is            => 'ro',
	isa           => 'ArrayRef[Str]',
	default       => sub {
		return ['localhost:9200'],
	},
	documentation => 'Elasticsearch nodes that should be used. Defaults to <localhost:9200>.',
);

has 'es' => (
	traits   => ['NoGetopt'],
	is       => 'ro',
	does     => 'Search::Elasticsearch::Role::Client::Direct',
	lazy     => 1,
	default  => sub {
		my ($self) = @_;
		return Search::Elasticsearch->new(
			nodes => $self->get_nodes(),
		);
	},
);

has 'date_parser' => (
	traits   => ['NoGetopt'],
	is       => 'ro',
	isa      => 'DateTime::Format::Strptime',
	lazy     => 1,
	default  => sub {
		return DateTime::Format::Strptime->new(
			pattern  => '%d/%b/%Y:%T %z',
			on_error => 'croak',
		);
	},
	handles => [ 'parse_datetime' ],
);

has 'log_parser' => (
	traits   => ['NoGetopt'],
	is       => 'ro',
	isa      => 'Apache::Log::Parser',
	lazy     => 1,
	default  => sub {
		return Apache::Log::Parser->new(fast => 1);
	},
	handles  => [ 'parse_fast' ],
);


=head2 run

Main method which parses the log file an injects it into Elasticsearch.

=head3 Result

Nothing on success, an exception otherwise.

=cut

sub run {
	my ($self) = @_;

	my $fh = $self->get_log()->openr();
	my $bulk = $self->get_es()->bulk_helper(
		index   => $self->get_index(),
		type    => $self->get_type(),
	);

	while (my $line = $fh->getline()) {
		my $parsed_line = $self->parse_fast($line);
		delete $parsed_line->{date};
		delete $parsed_line->{time};
		delete $parsed_line->{timezone};
		for my $key (grep { looks_like_number($parsed_line->{$_}) } qw(bytes status)) {
			$parsed_line->{$key} = $parsed_line->{$key} + 0;
		}

		$parsed_line->{'@timestamp'} = $self->parse_datetime(
			$parsed_line->{datetime}
		)->set_time_zone('UTC')->strftime('%FT%TZ');
		$parsed_line->{vhost} = $self->get_vhost();
		if (defined $self->get_host()) {
			$parsed_line->{host} = $self->get_host();
		}

		$bulk->create_docs($parsed_line);
	}
	$bulk->flush();
}


__PACKAGE__->meta->make_immutable();

__PACKAGE__->new_with_options()->run() unless caller();

1;

=head1 SEE ALSO

=over

=item *

L<Search::Elasticsearch|Search::Elasticsearch> - Elasticsearch client which is
used.

=item *

L<http://www.elasticsearch.org/overview/kibana/> - Kibana, a web-based interface
to interact with data in Elasticsearch.

=back

=cut
