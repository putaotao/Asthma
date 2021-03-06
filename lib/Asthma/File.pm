package Asthma::File;
use Moose::Role;
use namespace::autoclean;
use XML::Twig;
use Asthma::Debug;

has 'xml_twig' => ( is => 'rw', isa => 'XML::Twig', lazy_build => 1 );

sub _build_xml_twig {
    my $self = shift;
    my $twig = XML::Twig->new();
    return $twig;
}

sub wf {
    my $self = shift;
    my $items = $self->{items};
    return unless $items && ref($items) eq "ARRAY";

    my $chunk_num = $self->chunk_num;
    
    my @now = localtime();
    my $date = sprintf("%04d%02d%02d-%02d%02d%02d", $now[5]+1900, $now[4]+1, $now[3], $now[2], $now[1], $now[0]);

    my $file;
    my $pn = ref($self);
    if ( $pn =~ m{Spider::(.+)} ) {
	$file = "/var/file/" . $1 . "_${chunk_num}_$date.xml";
    }
    return unless $file;

    my $add = XML::Twig::Elt->new("add");
    $self->xml_twig->set_root($add);

    foreach my $item ( @$items ) {
	$item->id($item->sku . "-" . $self->site_id);

	my $doc = XML::Twig::Elt->new("doc");	
	foreach my $attr (@{$item->solr_field}) {
		next unless $item->$attr;
		my $elt = XML::Twig::Elt->new(field => $item->$attr);
		$elt->set_att(name => $attr);
		$elt->paste($doc);	
	}

	my $elt = XML::Twig::Elt->new(field => $self->site_id);
	$elt->set_att(name => 'site_id');
	$elt->paste($doc);

	$doc->paste($add);
    }

    debug("write to file $file");
    $self->xml_twig->print_to_file($file);
}

1;

