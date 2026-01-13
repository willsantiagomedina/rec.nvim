use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::Duration;

use dirs::home_dir;
use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;

const PID_FILE: &str = "/tmp/rec.nvim.pid";
const OUT_FILE: &str = "/tmp/rec.nvim.outpath";
const LOG_FILE: &str = "/tmp/rec.nvim.ffmpeg.log";

fn default_output_path() -> PathBuf {
    // Use ~/Movies/rec.nvim.mp4 if possible, otherwise fallback to ~/rec.nvim.mp4
    let home = home_dir().unwrap_or_else(|| PathBuf::from("."));
    let movies = home.join("Movies");
    if movies.exists() {
        movies.join("rec.nvim.mp4")
    } else {
        home.join("rec.nvim.mp4")
    }
}

fn ensure_parent_dir(path: &Path) {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
}

fn write_log_header(msg: &str) {
    let mut f = OpenOptions::new()
        .create(true)
        .append(true)
        .open(LOG_FILE)
        .expect("failed to open log file");
    let _ = writeln!(f, "\n===== {} =====", msg);
}

fn read_pid() -> Option<i32> {
    fs::read_to_string(PID_FILE).ok()?.trim().parse::<i32>().ok()
}

fn pid_is_alive(pid: i32) -> bool {
    // kill(pid, None) is a standard "exists?" check on Unix
    kill(Pid::from_raw(pid), None).is_ok()
}

fn cmd_devices() {
    // This prints avfoundation device list into your terminal (not Neovim notify)
    // Useful to find the correct screen index: "Capture screen 0"
    let mut c = Command::new("ffmpeg");
    c.args(["-f", "avfoundation", "-list_devices", "true", "-i", ""]);
    c.stdout(Stdio::inherit());
    c.stderr(Stdio::inherit());

    let status = c.status().expect("failed to run ffmpeg device listing");
    if !status.success() {
        eprintln!("ffmpeg device listing exited non-zero");
    }
}

fn cmd_start(device: &str, out: Option<PathBuf>) {
    if let Some(pid) = read_pid() {
        if pid_is_alive(pid) {
            println!("REC_ALREADY_RUNNING");
            return;
        } else {
            // stale pid file
            let _ = fs::remove_file(PID_FILE);
        }
    }

    let output = out.unwrap_or_else(default_output_path);
    ensure_parent_dir(&output);

    // Persist output path so stop knows where to look
    let _ = fs::write(OUT_FILE, output.to_string_lossy().to_string());

    // Fresh log header
    write_log_header(&format!("START (device={}, output={})", device, output.display()));

    // Log file for ffmpeg stderr (THIS IS HOW WE SEE REAL ERRORS)
    let log = File::create(LOG_FILE).expect("failed to create ffmpeg log");

    // IMPORTANT: macOS avfoundation expects "<video>:<audio>"
    // For screen capture: "<screen_index>:none"
    let input = format!("{}:none", device);

    let child = Command::new("ffmpeg")
        .args([
            "-y",
            "-f",
            "avfoundation",
            "-framerate",
            "30",
            "-i",
            &input,
            "-pix_fmt",
            "yuv420p",
            output.to_str().unwrap(),
        ])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(log)
        .spawn()
        .expect("failed to start ffmpeg");

    let pid = child.id() as i32;
    fs::write(PID_FILE, pid.to_string()).expect("failed to write pid file");

    println!("REC_START_OK");
}

fn cmd_stop() {
    let pid = match read_pid() {
        Some(pid) => pid,
        None => {
            println!("REC_NOT_RUNNING");
            return;
        }
    };

    write_log_header(&format!("STOP (pid={})", pid));

    // Send SIGINT to finalize MP4
    let _ = kill(Pid::from_raw(pid), Signal::SIGINT);

    // Wait for process to exit (MP4 finalizes on shutdown)
    // up to ~5 seconds
    for _ in 0..50 {
        if !pid_is_alive(pid) {
            break;
        }
        thread::sleep(Duration::from_millis(100));
    }

    // Cleanup pid file regardless
    let _ = fs::remove_file(PID_FILE);

    // Determine output path from OUT_FILE
    let out_path = fs::read_to_string(OUT_FILE)
        .ok()
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|| default_output_path().to_string_lossy().to_string());

    let out = PathBuf::from(out_path);

    // Give filesystem a moment (sometimes ffmpeg flushes right after exit)
    for _ in 0..30 {
        if out.exists() && out.metadata().map(|m| m.len()).unwrap_or(0) > 0 {
            println!("REC_STOP_OK");
            println!("Saved to {}", out.display());
            return;
        }
        thread::sleep(Duration::from_millis(100));
    }

    // If we got here: file didn't appear
    // The ffmpeg log will explain why (permissions, wrong device index, etc.)
    println!("REC_STOP_ERR");
    println!("Check log: {}", LOG_FILE);
}

fn print_usage() {
    eprintln!(
        "usage:
  rec-cli devices
  rec-cli start <screen_index> [output_path]
  rec-cli stop

notes:
  - On macOS, list devices first:
      rec-cli devices
    Look for: 'Capture screen 0' (or 1, 2...)
  - ffmpeg errors are logged to:
      /tmp/rec.nvim.ffmpeg.log
"
    );
}

fn main() {
    let mut args = std::env::args().skip(1);

    match args.next().as_deref() {
        Some("devices") => cmd_devices(),
        Some("start") => {
let device = args.next().unwrap_or_else(|| "4".to_string());
            let out = args.next().map(PathBuf::from);
            cmd_start(&device, out);
        }
        Some("stop") => cmd_stop(),
        _ => print_usage(),
    }
}

