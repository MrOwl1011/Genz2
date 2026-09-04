<?php
// Content served by the demo Xtream panel (player_api.php in this folder).
//
// This exists so App Store / Play Store reviewers can log into a real,
// working Xtream account instead of a client-side fake — see player_api.php
// for why that distinction matters. Every stream below is public and
// openly licensed, safe to show to anyone:
//
//   - Big Buck Bunny, Tears of Steel — Blender Foundation open movies,
//     released under CC BY 3.0 (https://creativecommons.org/licenses/by/3.0/).
//   - The BipBop streams (both the Apple-hosted one and the CloudFront
//     mirror) are Apple's own published HLS test asset, used throughout
//     Apple's own HLS developer documentation.
//   - The "x36xhzz" stream is Mux's public HLS test asset, published at
//     https://test-streams.mux.dev for exactly this kind of use.
//
// None of this is meant to look like a "real" IPTV lineup — it only needs
// to exercise every feature the app advertises (live playback, VOD,
// series/episodes, offline download) with content nobody could mistake for
// unlicensed redistribution.

declare(strict_types=1);

const DEMO_USERNAME = 'demo';
const DEMO_PASSWORD = 'demo';

// Public, direct (non-HLS) file — this is what makes the download button
// appear, since DownloadsProvider.isDownloadable() only excludes .m3u8.
//
// The original picks here (Google's gtv-videos-bucket BigBuckBunny.mp4 and
// Akamai's bitdash-a Sintel stream) both went dead (HTTP 403) sometime
// after being chosen, and the short-clip replacement that followed caused
// its own confusion (a 10-second file makes the resume feature look broken
// — see the fix in PlayerScreen._saveCurrentPosition). This is now the
// real, full-length film (Blender Foundation's own 720p release, ~10
// minutes, 59MB), permanently hosted on archive.org rather than a
// third-party CDN — chosen specifically to stop rotating. Verified working
// as of 2026-08-13; if it ever 403/404s, re-check with a plain `curl -o
// /dev/null -w '%{http_code}'` before assuming the app is broken.
const BIG_BUCK_BUNNY_MP4 = 'https://archive.org/download/BigBuckBunny_124/Content/big_buck_bunny_720p_surround.mp4';
const TEARS_OF_STEEL_HLS = 'https://demo.unified-streaming.com/k8s/features/stable/video/tears-of-steel/tears-of-steel.ism/.m3u8';
const APPLE_BIPBOP_HLS = 'https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/bipbop_4x3_variant.m3u8';
const CLOUDFRONT_BIPBOP_HLS = 'https://d2zihajmogu5jn.cloudfront.net/bipbop-advanced/bipbop_16x9_variant.m3u8';

function demo_live_categories(): array
{
    return [
        ['category_id' => '1', 'category_name' => 'Demo Live', 'parent_id' => 0],
    ];
}

function demo_live_streams(): array
{
    return [
        [
            'stream_id' => 1001,
            'name' => 'Apple HLS Test Stream',
            'stream_icon' => '',
            'category_id' => '1',
            'num' => 1,
            'epg_channel_id' => '',
            'tv_archive' => 0,
            'direct_source' => APPLE_BIPBOP_HLS,
        ],
        [
            // Was Mux's test stream — confirmed working over HTTP but not
            // playing reliably on-device, unlike Apple's bipbop stream
            // (confirmed working end-to-end). Swapped for a second copy of
            // the same bipbop content family (CloudFront-hosted "advanced"
            // variant — same avc1.4d40xx/mp4a.40.2 codec profile as the
            // Apple one that's already proven to work) rather than keep
            // debugging a codec/device-specific issue blind.
            'stream_id' => 1002,
            'name' => 'HLS Test Stream 2',
            'stream_icon' => '',
            'category_id' => '1',
            'num' => 2,
            'epg_channel_id' => '',
            'tv_archive' => 0,
            'direct_source' => CLOUDFRONT_BIPBOP_HLS,
        ],
    ];
}

function demo_vod_categories(): array
{
    return [
        ['category_id' => '1', 'category_name' => 'Demo Movies', 'parent_id' => 0],
    ];
}

function demo_vod_streams(): array
{
    return [
        [
            'stream_id' => 101,
            'name' => 'Big Buck Bunny',
            'stream_icon' => 'https://peach.blender.org/wp-content/uploads/title_anouncement.jpg',
            'category_id' => '1',
            'container_extension' => 'mp4',
            'plot' => 'A giant rabbit deals with three bullying rodents, from the Blender Foundation open movie project. Full-length film, direct MP4 file — used here to demonstrate offline downloads.',
            'cast' => '',
            'director' => 'Sacha Goedegebure',
            'genre' => 'Animation',
            'releaseDate' => '2008-04-10',
            'rating' => '8',
            'rating_5based' => 4.0,
            'added' => (string) (time() - 86400 * 2),
            'num' => 1,
            'custom_sid' => '',
            'direct_source' => BIG_BUCK_BUNNY_MP4,
            'duration' => '00:09:56',
        ],
        [
            'stream_id' => 102,
            'name' => 'Tears of Steel',
            'stream_icon' => 'https://mango.blender.org/wp-content/uploads/2015/07/tos-poster.jpg',
            'category_id' => '1',
            'container_extension' => 'm3u8',
            'plot' => 'A group of warriors and scientists gather to stage a final stand against a robot army, from the Blender Foundation open movie project. Served as HLS.',
            'cast' => '',
            'director' => 'Ian Hubert',
            'genre' => 'Sci-Fi Short',
            'releaseDate' => '2012-09-26',
            'rating' => '8',
            'rating_5based' => 4.0,
            'added' => (string) (time() - 86400),
            'num' => 2,
            'custom_sid' => '',
            'direct_source' => TEARS_OF_STEEL_HLS,
            'duration' => '00:12:14',
        ],
    ];
}

function demo_series_categories(): array
{
    return [
        ['category_id' => '1', 'category_name' => 'Demo Series', 'parent_id' => 0],
    ];
}

function demo_series_list(): array
{
    return [
        [
            'series_id' => 201,
            'name' => 'Open Movie Shorts',
            'cover' => 'https://mango.blender.org/wp-content/uploads/2015/07/tos-poster.jpg',
            'category_id' => '1',
            'plot' => 'A two-part demo "series" made from Blender Foundation open movies, used to exercise episode playback and downloads.',
            'cast' => '',
            'director' => 'Blender Foundation',
            'genre' => 'Animation',
            'releaseDate' => '2012-09-26',
            'rating' => '8',
            'last_modified' => time() - 3600,
        ],
    ];
}

function demo_series_episodes(): array
{
    return [
        '1' => [
            [
                'id' => '1',
                'episode_num' => 1,
                'title' => 'Chapter 1 — Big Buck Bunny (downloadable)',
                'container_extension' => 'mp4',
                'info' => 'Direct MP4 file — downloadable, same as the movie entry.',
                'custom_sid' => '',
                'added' => time() - 86400 * 2,
                'season' => 1,
                'direct_source' => BIG_BUCK_BUNNY_MP4,
            ],
            [
                'id' => '2',
                'episode_num' => 2,
                'title' => 'Chapter 2 — HLS Test Stream',
                'container_extension' => 'm3u8',
                'info' => 'Served as HLS, like a typical live/VOD stream.',
                'custom_sid' => '',
                'added' => time() - 86400,
                'season' => 1,
                'direct_source' => CLOUDFRONT_BIPBOP_HLS,
            ],
        ],
    ];
}
