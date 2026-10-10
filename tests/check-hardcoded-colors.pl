#!/usr/bin/env perl

use strict;
use warnings;

my %named_color = map { $_ => 1 } qw(
    aliceblue antiquewhite aqua aquamarine azure beige bisque black
    blanchedalmond blue blueviolet brown burlywood cadetblue chartreuse
    chocolate coral cornflowerblue cornsilk crimson cyan darkblue darkcyan
    darkgoldenrod darkgray darkgreen darkgrey darkkhaki darkmagenta
    darkolivegreen darkorange darkorchid darkred darksalmon darkseagreen
    darkslateblue darkslategray darkslategrey darkturquoise darkviolet
    deeppink deepskyblue dimgray dimgrey dodgerblue firebrick floralwhite
    forestgreen fuchsia gainsboro ghostwhite gold goldenrod gray green
    greenyellow grey honeydew hotpink indianred indigo ivory khaki lavender
    lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan
    lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon
    lightseagreen lightskyblue lightslategray lightslategrey lightsteelblue
    lightyellow lime limegreen linen magenta maroon mediumaquamarine mediumblue
    mediumorchid mediumpurple mediumseagreen mediumslateblue mediumspringgreen
    mediumturquoise mediumvioletred midnightblue mintcream mistyrose moccasin
    navajowhite navy oldlace olive olivedrab orange orangered orchid
    palegoldenrod palegreen paleturquoise palevioletred papayawhip peachpuff
    peru pink plum powderblue purple rebeccapurple red rosybrown royalblue
    saddlebrown salmon sandybrown seagreen seashell sienna silver skyblue
    slateblue slategray slategrey snow springgreen steelblue tan teal thistle
    tomato turquoise violet wheat white whitesmoke yellow yellowgreen
);

sub usage {
    print STDERR "usage: perl tests/check-hardcoded-colors.pl FILE...\n";
    exit 2;
}

sub preserve_newlines {
    my ($text) = @_;
    $text =~ s/[^\n]//g;
    return $text;
}

sub read_input {
    my ($path) = @_;

    if ($path eq '-') {
        local $/;
        return ('<stdin>', <STDIN> // '');
    }

    open my $handle, '<', $path
        or return (undef, "cannot read $path: $!");
    local $/;
    my $content = <$handle> // '';
    close $handle;
    return ($path, $content);
}

my $border_property = qr/border(?:-(?:top|right|bottom|left))?(?:-color)?
                         |border-image(?:-source)?
                         |outline(?:-color)?/xi;

# Black or white with alpha below 1 only darkens or lightens whatever lies
# underneath, so it suits both palettes. It is allowed in border properties.
my $neutral_overlay = qr/\brgba\s*\(\s*(?:0\s*,\s*0\s*,\s*0|255\s*,\s*255\s*,\s*255)
                         \s*,\s*(?:0?\.\d+|0)\s*\)/xi;

my $shadow_property = qr/box-shadow|text-shadow|-gtk-icon-shadow/i;

# A black shadow reads as a shadow on both palettes, so shadows may use black
# in any form. White highlights must use @highlight_color, which is transparent
# in the dark palette.
my $black = qr/\brgba?\s*\(\s*0\s*,\s*0\s*,\s*0\s*(?:,\s*[\d.]+\s*)?\)
               |\#0{3}(?:0{3})?\b
               |\bblack\b/xi;

# Foreground tokens are dark in the light palette and light in the dark one,
# so a shadow made from them turns into a glow. Use @shade_color instead.
my $inverting_token = qr/\@(?:fg_color|text_color)(?![A-Za-z0-9_-])/;

sub scan_input {
    my ($label, $css) = @_;
    my $violations = 0;

    $css =~ s{/\*.*?\*/}{preserve_newlines($&)}gse;
    $css =~ s{\burl\s*\((?:[^()"']+|"[^"]*"|'[^']*')*\)}
             {'url()' . preserve_newlines($&)}gise;

    while ($css =~ /(?:\A|[;{}])\s*
                    (color|background-color|background-image|$border_property|$shadow_property)\s*:\s*
                    ([^;{}]*?)(?=;|}|\z)/gimsx) {
        my $property = $1;
        my $value = $2;
        my $property_offset = $-[1];
        my $is_shadow = $property =~ /\A(?:$shadow_property)\z/i;
        my $literal_value = $value;
        my $has_inverting_token = $is_shadow && $literal_value =~ $inverting_token;
        $literal_value =~ s/\@[A-Za-z_][A-Za-z0-9_-]*//g;
        $literal_value =~ s/$neutral_overlay//g
            if $property =~ /\A(?:$border_property)\z/i;
        $literal_value =~ s/$black//g if $is_shadow;
        my $has_literal =
            $has_inverting_token
            || $literal_value =~ /#[0-9a-fA-F]{3,8}\b/
            || $literal_value =~ /\brgba?\s*\(/i
            || $literal_value =~ /\bhsla?\s*\(/i
            || grep { $named_color{lc $_} }
                ($literal_value =~ /\b([A-Za-z]+)\b/g);

        next unless $has_literal;

        my $prefix = substr($css, 0, $property_offset);
        my $line = 1 + ($prefix =~ tr/\n//);
        my $display = $value;
        $display =~ s/\s+/ /g;
        $display =~ s/^\s+|\s+$//g;
        print "$label:$line: $property: $display\n";
        $violations++;
    }

    return $violations;
}

usage() unless @ARGV;

my $violations = 0;
my $read_errors = 0;

for my $path (@ARGV) {
    my ($label, $content_or_error) = read_input($path);
    if (!defined $label) {
        print STDERR "$content_or_error\n";
        $read_errors++;
        next;
    }
    $violations += scan_input($label, $content_or_error);
}

exit 2 if $read_errors;
exit 1 if $violations;
exit 0;
