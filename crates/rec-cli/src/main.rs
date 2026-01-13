use chrono::Local;
use clap::{Parser, Subcommand};
use dirs::home_dir;
use nix::sys::signal::{kill, Signal};
use nix::unistd::Pid;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::Duration;

const PID_FILE: &str = "/tmp/rec.nvim.pid";
const OUT_FILE: &str = "/tmp/rec.nvim.outpath";
const LOG_FILE: &str = "/tmp/rec.nvim.ffmpeg.log";

/*
  IMPORTANT (macOS avfoundation):
  From your device list:
    [4] Capture screen 0
*/
const SCREEN_INDEX: &str = "4";

#[derive(Parser, Debug)]
#[command(name = "rec-cli", version)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// List avfoundation devices
    Devices,

    /// Start recording (optionally cropped)
    Start {
        /// Output directory
        #[arg(long)]
        output_dir: Option<PathBuf>,

        /// Crop X (pixels)
        #[arg(long)]
        x: Option<i32>,
        /// Crop Y (pixels)
        #[arg(long)]
        y: Option<i32>,
        /// Crop width (pixels)
        #[arg(long)]
        width: Option<i32>,
        /// Crop height (pixels)
        #[arg(long)]
        height: Option<i32>,
    },

    /// Stop recording
Stop {
    /// Output directory (ignored, for compatibility)
    #[arg(long)]
    output_dir: Option<PathBuf>,
},


}

fn write_log(msg: &str) {
    let mut f = OpenOptions::new()
        .create(true)
        .append(true)
        .open(LOG_FILE)
        .expect("failed to open log file");
    let _ = writeln!(f, "{}", msg);
}

fn ensure_parent_dir(path: &Path) {
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }
}

fn read_pid() -> Option<i32> {
    fs::read_to_string(PID_FILE).ok()?.trim().parse().ok()
}

fn pid_alive(pid: i32) -> bool {
    kill(Pid::from_raw(pid), None).is_ok()
}

fn default_output_dir() -> PathBuf {
    let home = home_dir().unwrap_or_else(|| PathBuf::from("."));
    home.join("Videos").join("nvim-recordings")
}

fn next_output_file(dir: &Path) -> PathBuf {
    let ts = Local::now().format("%Y%m%d_%H%M%S");
    dir.join(format!("rec_{}.mp4", ts))
}

fn cmd_devices() -> anyhow::Result<()> {
    let status = Command::new("ffmpeg")
        .args(["-f", "avfoundation", "-list_devices", "true", "-i", ""])
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()?;

    if !status.success() {
        eprintln!("ffmpeg device listing failed");
    }
    Ok(())
}

fn cmd_start(
    output_dir: Option<PathBuf>,
    x: Option<i32>,
    y: Option<i32>,
    width: Option<i32>,
    height: Option<i32>,
) -> anyhow::Result<()> {
    if let Some(pid) = read_pid() {
        if pid_alive(pid) {
            println!("REC_ALREADY_RUNNING");
            return Ok(());
        }
        let _ = fs::remove_file(PID_FILE);
    }

    let dir = output_dir.unwrap_or_else(default_output_dir);
    fs::create_dir_all(&dir)?;
    let output = next_output_file(&dir);
    ensure_parent_dir(&output);

    fs::write(OUT_FILE, output.to_string_lossy().to_string())?;

    let input = format!("{}:none", SCREEN_INDEX);

    write_log("===== START =====");
    write_log(&format!("Input: {}", input));
    write_log(&format!("Output: {}", output.display()));

    let log = OpenOptions::new()
        .create(true)
        .append(true)
        .open(LOG_FILE)?;

    let mut cmd = Command::new("ffmpeg");
    cmd.args([
        "-y",

        // video input
        "-f", "avfoundation",
        "-framerate", "30",
        "-i", &input,

        // silent audio (QuickTime REQUIRES this)
        "-f", "lavfi",
        "-i", "anullsrc",

        // QuickTime-safe encoding
        "-pix_fmt", "yuv420p",
        "-profile:v", "high",
        "-level", "4.2",
        "-movflags", "+faststart",

        "-c:v", "libx264",
        "-preset", "ultrafast",
        "-crf", "23",

        // stop audio when video ends
        "-shortest",
    ]);

    // Apply crop only if all values exist (RecWin)
    if let (Some(x), Some(y), Some(w), Some(h)) = (x, y, width, height) {
        let filter = format!("crop={}:{}:{}:{}", w, h, x, y);
        write_log(&format!("Crop filter: {}", filter));
        cmd.args(["-filter:v", &filter]);
    }

    cmd.arg(&output)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(log);

    let child = cmd.spawn()?;
    let pid = child.id() as i32;
    fs::write(PID_FILE, pid.to_string())?;

    // give ffmpeg time to crash if misconfigured
    thread::sleep(Duration::from_millis(400));
    if !pid_alive(pid) {
        println!("REC_START_ERR");
        println!("ffmpeg exited immediately");
        println!("Log: {}", LOG_FILE);
        return Ok(());
    }

    println!("Recording started");
    println!("Output: {}", output.display());
    Ok(())
}

fn cmd_stop() -> anyhow::Result<()> {
    let pid = match read_pid() {
        Some(p) => p,
        None => {
            println!("REC_NOT_RUNNING");
            return Ok(());
        }
    };

    write_log("===== STOP =====");
    let _ = kill(Pid::from_raw(pid), Signal::SIGINT);

    for _ in 0..50 {
        if !pid_alive(pid) {
            break;
        }
        thread::sleep(Duration::from_millis(100));
    }

    let _ = fs::remove_file(PID_FILE);

    let out_path = fs::read_to_string(OUT_FILE).unwrap_or_default();
    let out = PathBuf::from(out_path.trim());

    // wait for mp4 to finalize
    for _ in 0..30 {
        if out.exists() && out.metadata().map(|m| m.len()).unwrap_or(0) > 0 {
            println!("Recording stopped");
            println!("Recording saved: {}", out.display());
            return Ok(());
        }
        thread::sleep(Duration::from_millis(100));
    }

    println!("REC_STOP_ERR");
    println!("Check log: {}", LOG_FILE);
    Ok(())
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Devices => cmd_devices()?,
        Commands::Start { output_dir, x, y, width, height } => {
            cmd_start(output_dir, x, y, width, height)?
        }
Commands::Stop { .. } => cmd_stop()?,
    }

    Ok(())
}

