package Asthma::Item;
use Moose;

use Data::Dumper;

has ['name', 'image_url', 'ean'] => (is => 'rw', isa => 'Str');
has 'price' => (is => 'rw');

before 'ean' => sub {
    if ( my $ean = $_[1] ) {
	$ean =~ s{[^\d]}{}g;
	$_[1] = $ean;
    }
};

before 'price' => sub {
    if ( my $price = $_[1] ) {
	$price =~ s{[^\d.,]}{}g;
	$_[1] = $price;
    }
};

no Moose;
__PACKAGE__->meta->make_immutable;

1;
