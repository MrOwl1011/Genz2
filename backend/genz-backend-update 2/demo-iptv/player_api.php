<?php
// A real, minimal Xtream Codes–compatible API endpoint, used only as the
// account App Store / Play Store reviewers log into.
//
// Why this exists: GenZ+ used to detect a magic "server=demo" login on the
// client and swap in fake, fully local data instead of ever making a
// network call — reviewers got a different app than real users. Apple
// rejected that under Guideline 5.6 (Developer Code of Conduct) for
// exactly what it was: hidden/different behavior during review. That
// client-side branch has been removed entirely.
//
// This file replaces it. It is a REAL server, speaking the REAL Xtream
// protocol the app already talks to for any other provider — there is no
// special-casing left in the app at all. The only thing "fake" about this
// account is that its content is a small set of openly-licensed public
// test videos (see demo_content.php) instead of a live IPTV lineup, which
// is exactly what makes it safe to hand to a reviewer.
//
// Credentials: username=demo, password=demo (see DEMO_USERNAME/DEMO_PASSWORD
// in demo_content.php). Server URL for App Review Notes: this file's own
// URL, e.g. https://api.shitaa.online/demo-iptv (the app appends
// /player_api.php itself).

declare(strict_types=1);

require __DIR__ . '/demo_content.php';

header('Content-Type: application/json; charset=utf-8');

$username = trim((string) ($_GET['username'] ?? ''));
$password = trim((string) ($_GET['password'] ?? ''));
$action = trim((string) ($_GET['action'] ?? ''));

$authed = strtolower($username) === DEMO_USERNAME && strtolower($password) === DEMO_PASSWORD;

function user_info(bool $authed): array
{
    return [
        'user_info' => [
            'auth' => $authed ? 1 : 0,
            'status' => $authed ? 'Active' : 'Disabled',
            'message' => $authed ? '' : 'Invalid username or password',
            'exp_date' => null, // null → shown as unlimited/lifetime in the app
            'is_trial' => '0',
            'active_cons' => '0',
            'created_at' => (string) (time() - 86400 * 30),
            'max_connections' => '1',
            'allowed_output_formats' => ['m3u8', 'ts', 'mp4'],
        ],
        'server_info' => [
            'url' => $_SERVER['HTTP_HOST'] ?? 'api.shitaa.online',
            'server_protocol' => 'https',
            'timezone' => 'UTC',
        ],
    ];
}

if (!$authed) {
    // Matches how a real panel responds to a bad login, and how every
    // other action responds once auth has failed — empty/denied, not an
    // HTTP error, so the app's existing error handling (which reads
    // user_info.auth) is what surfaces the message.
    http_response_code(200);
    echo json_encode($action === '' ? user_info(false) : []);
    exit;
}

switch ($action) {
    case '':
        // No action = the initial login call (see XtreamApiService.authenticate).
        echo json_encode(user_info(true));
        break;

    case 'get_live_categories':
        echo json_encode(demo_live_categories());
        break;

    case 'get_live_streams':
        $streams = demo_live_streams();
        $categoryId = $_GET['category_id'] ?? null;
        if ($categoryId !== null) {
            $streams = array_values(array_filter(
                $streams,
                fn ($s) => $s['category_id'] === (string) $categoryId
            ));
        }
        echo json_encode($streams);
        break;

    case 'get_vod_categories':
        echo json_encode(demo_vod_categories());
        break;

    case 'get_vod_streams':
        $streams = demo_vod_streams();
        $categoryId = $_GET['category_id'] ?? null;
        if ($categoryId !== null) {
            $streams = array_values(array_filter(
                $streams,
                fn ($s) => $s['category_id'] === (string) $categoryId
            ));
        }
        echo json_encode($streams);
        break;

    case 'get_vod_info':
        $vodId = (int) ($_GET['vod_id'] ?? 0);
        $movie = null;
        foreach (demo_vod_streams() as $stream) {
            if ($stream['stream_id'] === $vodId) {
                $movie = $stream;
                break;
            }
        }
        if ($movie === null) {
            echo json_encode(new stdClass());
            break;
        }
        echo json_encode([
            'info' => [
                'movie_image' => $movie['stream_icon'],
                'plot' => $movie['plot'],
                'cast' => $movie['cast'],
                'director' => $movie['director'],
                'genre' => $movie['genre'],
                'releasedate' => $movie['releaseDate'],
                'rating' => $movie['rating'],
                'duration' => $movie['duration'] ?? '00:00:00',
            ],
            'movie_data' => $movie,
        ]);
        break;

    case 'get_series':
        $series = demo_series_list();
        $categoryId = $_GET['category_id'] ?? null;
        if ($categoryId !== null) {
            $series = array_values(array_filter(
                $series,
                fn ($s) => $s['category_id'] === (string) $categoryId
            ));
        }
        echo json_encode($series);
        break;

    case 'get_series_info':
        $seriesId = (int) ($_GET['series_id'] ?? 0);
        $series = null;
        foreach (demo_series_list() as $s) {
            if ($s['series_id'] === $seriesId) {
                $series = $s;
                break;
            }
        }
        if ($series === null) {
            echo json_encode(new stdClass());
            break;
        }
        echo json_encode([
            'info' => $series,
            'episodes' => demo_series_episodes(),
        ]);
        break;

    default:
        // Unknown action — a real panel would 404 or return an empty body;
        // an empty array is the safest match for every list-shaped caller.
        echo json_encode([]);
        break;
}
