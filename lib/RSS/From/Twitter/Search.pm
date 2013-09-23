package RSS::From::Twitter::Search;

use 5.010001;
use strict;
use warnings;
use Log::Any qw($log);

use HTML::Entities;
use LWP::UserAgent;
use Mojo::DOM;
use Perinci::Sub::Util qw(err);
use POSIX;
use URI::Escape;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(get_rss_from_twitter_search);

# VERSION

our %SPEC;

$SPEC{get_rss_from_twitter_search} = {
    v => 1.1,
    summary => 'Convert Twitter search page to RSS',
    description => <<'_',

In June 2013, Twitter retired the RSS v1 API (e.g.
http://search.twitter.com/search.rss?q=blah). However, its replacement, the v1.1
API, is not as straightforward to use (e.g. needs auth). This function scrapes
the Twitter search result page (e.g. https://twitter.com/search?q=blah) and
converts it to RSS. I wrote this because I have other scripts expecting RSS
input.

Expect breakage from time to time though, as scraping method is rather fragile.

_
    args    => {
        query => {
            summary  => 'Search query',
            schema   => 'str*',
            pos      => 0,
            req      => 1,
        },
        ua => {
            summary     => 'Supply a custom LWP::UserAgent object',
            schema      => 'obj',
            description => <<'_',

If supplied, will be used instead of the default LWP::UserAgent object.

_
        },
    },
};
sub get_rss_from_twitter_search {
    my %args = @_;

    my $datefmt = "%a, %d %b %Y %H:%M:%S %z";
    state $default_ua = LWP::UserAgent->new;

    my $query = $args{query};
    defined $query or return err(400, "Please specify query");
    my $ua    = $args{ua} // $default_ua;

    my $url = "https://twitter.com/search?q=".uri_escape($query);
    my $uares;
    eval { $uares = $ua->get($url) };
    return err(500, "Can't download URL `$url`: $@") if $@;
    return err($uares->code, "Can't download URL: " . $uares->message)
        unless $uares->is_success;

    my $dom;
    eval { $dom = Mojo::DOM->new($uares->content) };
    return err(500, "Can't create DOM from read URL: $@") if $@;

    my $gen = "RSS::From::Twitter::Search " .
        ($RSS::From::Twitter::Search::VERSION // "?"). " (Perl module)";

    my @rss;

    push @rss, '<?xml version="1.0" encoding="UTF-8">',"\n";
    push @rss, "<!-- generator=$gen -->\n";
    push @rss, ('<rss version="2.0"',
                ' xmlns:content="http://purl.org/rss/1.0/modules/content/"',
                ' xmlns:wfw="http://wellformedweb.org/CommentAPI/"',
                ' xmlns:dc="http://purl.org/dc/elements/1.1/"',
                ' xmlns:atom="http://www.w3.org/2005/Atom"',
                ' xmlns:sy="http://purl.org/rss/1.0/modules/syndication/"',
                ' xmlns:slash="http://purl.org/rss/1.0/modules/slash/"',
                ">\n");
    push @rss, "<channel>\n";
    push @rss, "<title>",encode_entities("Twitter Search: $query"),"</title>\n";
    push @rss, "<link>$url</link>\n";
    push @rss, "<generator>$gen</generator>\n";
    push @rss, "<lastBuildDate>",
        POSIX::strftime($datefmt, gmtime),
              "</lastBuildDate>\n";
    push @rss, "\n";

    my $tweets = $dom->find("div.tweet");
    for my $tweet (@$tweets) {
        my $html = "$tweet";
        my ($url) = $html =~ m!(/[^/]+/status/\d+)!;
        my $fullname = $tweet->find(".fullname")->text;
        my ($username) = $tweet->find(".username") =~ m!<b>(.+)</b>!;
        my $text = $tweet->find(".tweet-text"); $text = "$text"; $text =~ s!<.+?>!!sg;
        my ($time) = $tweet->find(".tweet-timestamp") =~ /data-time="(\d+)"/;

        push @rss, "<item>\n";
        push @rss, "<title>$fullname (\@$username)</title>\n";
        push @rss, "<link>https://twitter.com$url</link>\n";
        push @rss, "<pubDate>",
            strftime($datefmt, gmtime($time)),
                "</pubDate>\n";
        push @rss, "<description>$text</description>\n";
        push @rss, "</item>\n\n";
    }

    push @rss, "</channel>\n";
    push @rss, "</rss>\n";

    [200, "OK", join("", @rss)];
}

1;
#ABSTRACT: Convert Twitter search page to RSS

=head1 SYNOPSIS

 # See get-rss-from-twitter-search for command-line usage


=cut
