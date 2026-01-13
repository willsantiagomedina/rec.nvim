use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "rec-cli")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    Start,
    Stop,
    Status,
}

fn main() {
    let cli = Cli::parse();

    match cli.command {
        Commands::Start => println!("REC_START"),
        Commands::Stop => println!("REC_STOP"),
        Commands::Status => println!("REC_STATUS"),
    }
}
