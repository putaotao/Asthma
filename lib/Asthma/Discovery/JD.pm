package Asthma::Discovery::JD;
use Moose;
extends 'Asthma::Discovery';

use Coro;
use AnyEvent::HTTP;
use HTTP::Headers;
use HTTP::Message;
use Asthma::Debug;
use HTML::TreeBuilder;
use Data::Dumper;
use Asthma::LinkExtractor;
use Digest::MD5 qw(md5_base64);

has 'list_link_extractor' => (is => 'rw', lazy_build => 1);
has 'item_link_extractor' => (is => 'rw', lazy_build => 1);

sub _build_list_link_extractor {
    my $self = shift;
    my $link_extractor = Asthma::LinkExtractor->new();
    $link_extractor->allow(['list\.jd\.com/652-']);
    $link_extractor->allow(['list\.jd\.com/737-']);
    $link_extractor->allow(['list\.jd\.com/670-']);
    return $link_extractor;
}

sub _build_item_link_extractor {
    my $self = shift;
    my $link_extractor = Asthma::LinkExtractor->new();
    $link_extractor->allow(['item\.jd\.com/\d+\.html']);
    return $link_extractor;
}

sub BUILD {
    my $self = shift;
    $self->site_id(102);
    $self->start_url('http://www.jd.com/allSort.aspx');
}

sub run {
    my $self = shift;
    
    $self->start_find_urls;

    my $run = 1;
    my $start = 0;
    while ( $run ) {
        last unless $start = $self->find_urls($start);
    }
}

sub start_find_urls {
    my $self = shift;
    my $resp = $self->ua->get($self->start_url);
    my @urls = $self->list_link_extractor->extract_links($resp);

    foreach my $url ( @urls ) {
	my $md5_link = md5_base64($url);
	my $now = "now()";

	my $u = $self->storage->mysql->resultset('102ListUrls')->find_or_new({ link => $url,
									       md5_link => $md5_link,
									       dt_created => \$now,
									       dt_updated => \$now,
									     }, {key => 'md5_link'});
	if ( ! $u->in_storage ) {
	    debug("url $url with md5 $md5_link need to be added");
	    $u->insert;
	} else {
	    debug("url $url with md5 $md5_link and list_url_id " . $u->list_url_id . " exists");
	}
    }
}

sub find_urls {
    my ($self, $start) = @_;

    my $rows = 100;
    my $urls = [$self->storage->mysql->resultset($self->site_id . 'ListUrls')->search(
		    undef,
		    {
			offset => $start,
			rows   => $rows,
		    })];


    my $rs = $self->storage->mysql->resultset($self->site_id . 'ListUrls')->search();
    my $count = $rs->count;
    
    if ( $count < ($start+$rows) ) {
	$rows = $count - $start;
    }

    debug("start: $start, rows: $rows");

    if ( @$urls ) {
        my $sem = Coro::Semaphore->new(100);
        my @coros;

        foreach my $url_object ( @$urls ) {
	    my $url = $url_object->link;

            push @coros,
            async {
                my $guard = $sem->guard;

                http_get $url,
                headers => $self->headers,
                Coro::rouse_cb;

                my ($body, $hdr) = Coro::rouse_wait;

		debug("$hdr->{Status} $hdr->{Reason} $hdr->{URL}");

                my $header = HTTP::Headers->new('content-encoding' => 'gzip, deflate', 'content-type' => 'text/html');
                my $mess = HTTP::Message->new( $header, $body );
                my $content = $mess->decoded_content(charset => 'gbk');
                
                my @item_urls = $self->item_link_extractor->extract_links($content, $url);
                foreach my $item_url ( @item_urls ) {
		    my $md5_link = md5_base64($item_url);
		    my $now = "now()";

		    my $u = $self->storage->mysql->resultset($self->site_id . 'ItemUrls')->find_or_new({ link => $item_url,
													 md5_link => $md5_link,
													 dt_created => \$now,
													 dt_updated => \$now,
												       }, {key => 'md5_link'});
		    if ( ! $u->in_storage ) {
			debug("url $item_url with md5 $md5_link need to be added");
			$u->insert;
		    } else {
			debug("url $item_url with md5 $md5_link and item_url_id " . $u->item_url_id . " exists");
		    }
                }

                my $tree = HTML::TreeBuilder->new_from_content($content);
                if ( $tree->look_down('class', 'pagin pagin-m') ) {
                    if ( $tree->look_down('class', 'pagin pagin-m')->look_down("class", "next") ) {
                        if ( my $page_url = $tree->look_down('class', 'pagin pagin-m')->look_down("class", "next")->attr("href") ) {
                            $page_url = URI->new_abs($page_url, $url)->as_string;
                            
			    my $md5_link = md5_base64($page_url);
			    my $now = "now()";

			    my $u = $self->storage->mysql->resultset($self->site_id . 'ListUrls')->find_or_new({ link => $page_url,
														 md5_link => $md5_link,
														 dt_created => \$now,
														 dt_updated => \$now,
													       }, {key => 'md5_link'});
			    if ( ! $u->in_storage ) {
				debug("url $page_url with md5 $md5_link need to be added");
				$u->insert;
			    } else {
				debug("url $page_url with md5 $md5_link and list_url_id " . $u->list_url_id . " exists");
			    }
                        }
                    }
                }
                $tree->delete;
            }
        }

        $_->join foreach ( @coros );

        return $start+$rows;
    } else {
        return 0;
    }
}

__PACKAGE__->meta->make_immutable;

1;
