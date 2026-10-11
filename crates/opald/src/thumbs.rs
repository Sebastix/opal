//! Pictures from strangers, made safe for the shell.
//!
//! Profile pictures and album art are URLs someone else chose. The shell
//! never loads them itself: Qt's network image path reads the whole
//! response before decoding, and a small, highly compressed image can
//! decode to gigabytes. Instead opald fetches the bytes (at most
//! `MAX_BYTES`, within a deadline), and a short-lived `opald thumbnail`
//! child decodes them under memory and CPU limits, away from the keys this
//! process holds, and writes a `SIZE`-pixel PNG. The shell and the
//! notification popups only ever get that small PNG from Opal's cache.

use std::collections::HashMap;
use std::io::{Cursor, Read, Write};
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::sync::{LazyLock, Mutex, Once};
use std::time::{Duration, Instant};

use tokio::io::AsyncReadExt;
use tokio::process::Command;
use tokio::sync::Semaphore;

/// Longest side of a thumbnail, in pixels.
pub const SIZE: u32 = 256;
/// Largest picture fetched or read.
const MAX_BYTES: usize = 1 << 20;
/// Larger images aren't decoded at all.
const MAX_DIMENSION: u32 = 8192;
/// What the decoder may allocate, and the child's data limit around it.
const MAX_ALLOC: u64 = 128 << 20;
const CHILD_DATA_LIMIT: u64 = 384 << 20;
const CHILD_CPU_SECONDS: u64 = 5;
/// The whole fetch, and the whole decode, each end by then.
const FETCH_DEADLINE: Duration = Duration::from_secs(8);
const DECODE_DEADLINE: Duration = Duration::from_secs(10);
/// A thumbnail is a few hundred KiB at most; anything bigger is refused.
const MAX_THUMB_BYTES: usize = 2 << 20;
/// Files kept in the cache, and how long a failed URL isn't tried again.
const CACHE_MAX: usize = 500;
const RETRY_AFTER: Duration = Duration::from_secs(600);

/// A few at a time, so a page of avatars doesn't start dozens of fetches.
static GATE: LazyLock<Semaphore> = LazyLock::new(|| Semaphore::new(3));
static FAILED: LazyLock<Mutex<HashMap<u64, Instant>>> = LazyLock::new(Default::default);

/// The cached thumbnail of `url` (https, or a local file:// a music player
/// named), making it first if need be. `None` if it can't be fetched or
/// isn't an image.
pub async fn thumbnail(url: &str) -> Option<PathBuf> {
    if url.len() > 4096 || !(url.starts_with("https://") || url.starts_with("file://")) {
        return None;
    }
    static OLD_CACHE: Once = Once::new();
    OLD_CACHE.call_once(|| {
        // Before thumbnails, raw downloads went here.
        let _ = std::fs::remove_dir_all(opal_core::paths::cache_dir().join("avatars"));
    });
    let dir = opal_core::paths::cache_dir().join("thumbs");
    let key = fnv(url);
    let path = dir.join(format!("{key:016x}.png"));
    if path.metadata().is_ok_and(|m| m.len() > 0) {
        return Some(path);
    }
    if FAILED
        .lock()
        .unwrap()
        .get(&key)
        .is_some_and(|t| t.elapsed() < RETRY_AFTER)
    {
        return None;
    }
    let _permit = GATE.acquire().await.ok()?;
    // Made by another request while this one waited.
    if path.metadata().is_ok_and(|m| m.len() > 0) {
        return Some(path);
    }
    match make(url, &dir, &path).await {
        Some(()) => {
            prune(&dir);
            Some(path)
        }
        None => {
            let mut failed = FAILED.lock().unwrap();
            failed.retain(|_, t| t.elapsed() < RETRY_AFTER);
            failed.insert(key, Instant::now());
            None
        }
    }
}

async fn make(url: &str, dir: &Path, path: &Path) -> Option<()> {
    let bytes = if url.starts_with("https://") {
        download(url).await?
    } else {
        read_local(url).await?
    };
    let png = decode_in_child(bytes).await?;
    std::fs::create_dir_all(dir).ok()?;
    let tmp = path.with_extension(format!("{}.part", std::process::id()));
    if std::fs::write(&tmp, &png).is_ok() && std::fs::rename(&tmp, path).is_ok() {
        Some(())
    } else {
        let _ = std::fs::remove_file(&tmp);
        None
    }
}

/// At most `MAX_BYTES + 1` bytes of `url`, read from curl as they arrive:
/// curl's own `--max-filesize` can't stop a response without a length.
async fn download(url: &str) -> Option<Vec<u8>> {
    download_with("curl", url).await
}

async fn download_with(curl: &str, url: &str) -> Option<Vec<u8>> {
    let mut child = Command::new(curl)
        .args([
            "-fsL",
            "--max-time",
            "6",
            "--max-filesize",
            &MAX_BYTES.to_string(),
            "--max-redirs",
            "3",
            "--proto",
            "=https",
            "--proto-redir",
            "=https",
            "--",
            url,
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .ok()?;
    let mut out = child.stdout.take()?;
    let read = async {
        let mut buf = Vec::new();
        (&mut out)
            .take(MAX_BYTES as u64 + 1)
            .read_to_end(&mut buf)
            .await
            .ok()?;
        (buf.len() <= MAX_BYTES).then_some(buf)
    };
    let buf = tokio::time::timeout(FETCH_DEADLINE, read).await.ok()??;
    drop(out);
    let status = tokio::time::timeout(Duration::from_secs(2), child.wait())
        .await
        .ok()?
        .ok()?;
    (status.success() && !buf.is_empty()).then_some(buf)
}

/// A music player's local art: a regular file, at most `MAX_BYTES`.
async fn read_local(url: &str) -> Option<Vec<u8>> {
    let path = url::Url::parse(url).ok()?.to_file_path().ok()?;
    tokio::task::spawn_blocking(move || {
        // Checked before opening, so a FIFO or a device is never opened.
        if !std::fs::metadata(&path).ok()?.is_file() {
            return None;
        }
        let f = std::fs::File::open(&path).ok()?;
        if !f.metadata().ok()?.is_file() {
            return None;
        }
        let mut buf = Vec::new();
        f.take(MAX_BYTES as u64 + 1).read_to_end(&mut buf).ok()?;
        (!buf.is_empty() && buf.len() <= MAX_BYTES).then_some(buf)
    })
    .await
    .ok()?
}

async fn decode_in_child(bytes: Vec<u8>) -> Option<Vec<u8>> {
    // /proc/self/exe still runs after an upgrade replaced the file.
    let mut child = Command::new("/proc/self/exe")
        .arg("thumbnail")
        .env_clear()
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .kill_on_drop(true)
        .spawn()
        .ok()?;
    let mut stdin = child.stdin.take()?;
    let mut stdout = child.stdout.take()?;
    let run = async {
        use tokio::io::AsyncWriteExt;
        let write = async {
            let _ = stdin.write_all(&bytes).await;
            drop(stdin);
        };
        let read = async {
            let mut png = Vec::new();
            (&mut stdout)
                .take(MAX_THUMB_BYTES as u64 + 1)
                .read_to_end(&mut png)
                .await
                .ok()
                .map(|_| png)
        };
        let ((), png) = tokio::join!(write, read);
        let status = child.wait().await.ok()?;
        let png = png?;
        (status.success() && !png.is_empty() && png.len() <= MAX_THUMB_BYTES).then_some(png)
    };
    tokio::time::timeout(DECODE_DEADLINE, run).await.ok()?
}

/// `opald thumbnail`: an image on stdin, its PNG thumbnail on stdout.
/// Runs in a fresh process with nothing of opald's but the binary.
pub fn child_main() -> std::process::ExitCode {
    use rustix::process::{Resource, Rlimit, setrlimit};
    let limit = |r, n| {
        setrlimit(
            r,
            Rlimit {
                current: Some(n),
                maximum: Some(n),
            },
        )
    };
    if limit(Resource::Data, CHILD_DATA_LIMIT).is_err()
        || limit(Resource::Cpu, CHILD_CPU_SECONDS).is_err()
    {
        return std::process::ExitCode::FAILURE;
    }
    let mut input = Vec::new();
    if std::io::stdin()
        .take(MAX_BYTES as u64 + 1)
        .read_to_end(&mut input)
        .is_err()
        || input.len() > MAX_BYTES
    {
        return std::process::ExitCode::FAILURE;
    }
    match render(&input) {
        Some(png) if std::io::stdout().write_all(&png).is_ok() => std::process::ExitCode::SUCCESS,
        _ => std::process::ExitCode::FAILURE,
    }
}

/// Decode within limits and shrink to fit `SIZE`.
fn render(input: &[u8]) -> Option<Vec<u8>> {
    render_within(input, MAX_DIMENSION, MAX_ALLOC)
}

fn render_within(input: &[u8], max_dimension: u32, max_alloc: u64) -> Option<Vec<u8>> {
    let mut reader = image::ImageReader::new(Cursor::new(input))
        .with_guessed_format()
        .ok()?;
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(max_dimension);
    limits.max_image_height = Some(max_dimension);
    limits.max_alloc = Some(max_alloc);
    reader.limits(limits);
    let img = reader.decode().ok()?;
    let img = if img.width() > SIZE || img.height() > SIZE {
        img.thumbnail(SIZE, SIZE)
    } else {
        img
    };
    let thumb = image::DynamicImage::ImageRgba8(img.into_rgba8());
    let mut png = Vec::new();
    thumb
        .write_to(&mut Cursor::new(&mut png), image::ImageFormat::Png)
        .ok()?;
    Some(png)
}

fn prune(dir: &Path) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    let mut files: Vec<(std::time::SystemTime, PathBuf)> = entries
        .flatten()
        .filter_map(|e| Some((e.metadata().ok()?.modified().ok()?, e.path())))
        .collect();
    if files.len() <= CACHE_MAX {
        return;
    }
    files.sort();
    for (_, p) in files.iter().take(files.len() - CACHE_MAX) {
        let _ = std::fs::remove_file(p);
    }
}

/// Small, stable hash for cache file names (not security-relevant).
pub fn fnv(s: &str) -> u64 {
    s.bytes().fold(0xcbf29ce484222325u64, |h, b| {
        (h ^ b as u64).wrapping_mul(0x100000001b3)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn png(w: u32, h: u32) -> Vec<u8> {
        let img = image::RgbaImage::from_pixel(w, h, image::Rgba([200, 30, 30, 255]));
        let mut out = Vec::new();
        image::DynamicImage::ImageRgba8(img)
            .write_to(&mut Cursor::new(&mut out), image::ImageFormat::Png)
            .unwrap();
        out
    }

    #[test]
    fn shrinks_to_fit() {
        let out = render(&png(1024, 512)).unwrap();
        let t = image::load_from_memory(&out).unwrap();
        assert_eq!((t.width(), t.height()), (SIZE, SIZE / 2));
        let small = image::load_from_memory(&render(&png(40, 40)).unwrap()).unwrap();
        assert_eq!(small.width(), 40, "small pictures aren't blown up");
    }

    #[test]
    fn refuses_what_isnt_a_safe_image() {
        assert!(render(b"not an image").is_none());
        assert!(render(b"<svg xmlns='http://www.w3.org/2000/svg'/>").is_none());
        // A tiny file that claims to be huge: refused from its header,
        // before anything is allocated for it.
        let bomb = png(MAX_DIMENSION + 1, 1);
        assert!(bomb.len() < 64 * 1024);
        assert!(render(&bomb).is_none());
        let wide = png(MAX_DIMENSION, 1);
        assert!(render(&wide).is_some(), "up to the limit is fine");
    }

    #[test]
    fn the_allocation_limit_holds() {
        // 1024×1024 RGBA decodes to 4 MiB from a file of a few KiB.
        let bomb = png(1024, 1024);
        assert!(bomb.len() < 64 * 1024, "{} bytes", bomb.len());
        assert!(render_within(&bomb, MAX_DIMENSION, 1 << 20).is_none());
        assert!(render_within(&bomb, MAX_DIMENSION, 8 << 20).is_some());
    }

    #[tokio::test]
    async fn local_art_must_be_a_small_regular_file() {
        assert!(read_local("file:///dev/zero").await.is_none());
        assert!(read_local("file:///nonexistent/x.png").await.is_none());
        let dir = std::env::temp_dir().join(format!("opal-thumbs-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let ok = dir.join("art.png");
        std::fs::write(&ok, png(10, 10)).unwrap();
        let url = url::Url::from_file_path(&ok).unwrap().to_string();
        assert!(read_local(&url).await.is_some());
        let big = dir.join("big.bin");
        std::fs::write(&big, vec![0u8; MAX_BYTES + 1]).unwrap();
        let url = url::Url::from_file_path(&big).unwrap().to_string();
        assert!(read_local(&url).await.is_none());
        std::fs::remove_dir_all(&dir).ok();
    }

    /// A stand-in for curl that runs `body` (ignoring its arguments).
    fn fake_curl(name: &str, body: &str) -> PathBuf {
        use std::os::unix::fs::PermissionsExt;
        let dir = std::env::temp_dir().join(format!("opal-fake-curl-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join(name);
        std::fs::write(&p, format!("#!/usr/bin/env bash\n{body}\n")).unwrap();
        std::fs::set_permissions(&p, std::fs::Permissions::from_mode(0o755)).unwrap();
        p
    }

    #[tokio::test]
    async fn downloads_end_bounded_whatever_the_server_does() {
        let url = "https://example.com/a.png";
        let run = |name: &'static str, body: String| async move {
            let curl = fake_curl(name, &body);
            let t = Instant::now();
            let got = download_with(curl.to_str().unwrap(), url).await;
            (got, t.elapsed())
        };
        let (got, _) = run("ok", "printf picture".into()).await;
        assert_eq!(got.as_deref(), Some(&b"picture"[..]));
        let (got, took) = run("endless", "exec yes".into()).await;
        assert!(got.is_none(), "an endless body is refused");
        assert!(took < Duration::from_secs(3), "{took:?}");
        let (got, _) = run("big", format!("head -c {} /dev/zero", MAX_BYTES + 1)).await;
        assert!(got.is_none(), "one byte over is refused");
        let (got, _) = run("exact", format!("head -c {MAX_BYTES} /dev/zero")).await;
        assert_eq!(got.map(|b| b.len()), Some(MAX_BYTES));
        let (got, _) = run("failed", "printf 'Not Found'; exit 22".into()).await;
        assert!(got.is_none(), "an HTTP error is refused");
        let (got, took) = run("silent", "exec sleep 60".into()).await;
        assert!(got.is_none());
        assert!(took <= FETCH_DEADLINE + Duration::from_secs(1), "{took:?}");
    }

    #[tokio::test]
    async fn only_https_and_file_urls() {
        for bad in [
            "http://example.com/a.png",
            "data:image/png;base64,AAAA",
            "ftp://x/y",
            "/etc/passwd",
        ] {
            assert!(thumbnail(bad).await.is_none(), "{bad}");
        }
    }
}
