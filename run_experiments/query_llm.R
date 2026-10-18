# Sources ---------------------------------------------------------------------
source("source/reviewer.R")
source("source/configuration.R")
source("source/llm.R")

# Configuration ---------------------------------------------------------------
output_dir <- "output"                     # private persistent directory; required to send
model <- "thinker"                   # choose from list_models()
max_tokens <- 8192L                   # includes reasoning where applicable
credentials_file <- path.expand("~/.config/einfra-data-reviewer/credentials.R")
reasoning_effort <- NULL              # omit unverified model-specific controls
max_input_bytes <- 24000L             # byte budget, not an exact token count
send_to_api <- FALSE                  # explicitly enable after reviewing the prompt

# Editable prompt sections ===================================================
role <- "You are a scientific research assistant reviewing environmental data processing."
context <- paste(
  "This is a bounded, single-request task. You receive only the evidence below.",
  "There is no browsing, tool access, file access, or memory of earlier requests."
)
task <- "Review the supplied example and explain whether the documented operation matches its stated intent."
constraints <- paste(
  "Separate observed facts, likely explanations and uncertainties.",
  "Explain straightforward mathematical errors directly; do not hedge about established arithmetic.",
  "Do not invent citations, data or processing steps. Identify missing evidence.",
  "Do not recommend overwriting original data."
)
output_format <- paste(
  "Return Markdown with: Finding; Evidence and reasoning; Next action; Remaining uncertainty.",
  "Use at most 400 words and put the main finding first."
)
success_criteria <- paste(
  "Answer the specific task using supplied evidence, rather than repeating generic advice.",
  "Make any proposed explanation testable."
)
evidence_text <- paste(
  "Synthetic example, not a real dataset:",
  "Intended operation: convert Kelvin to Celsius.",
  "Recorded operation: add 273.15 to the original values."
)
evidence_files <- character()         # optional explicit UTF-8 text paths; no automatic file discovery

# Build and preview -----------------------------------------------------------
paths <- project_paths(output_dir = output_dir)
file_evidence <- read_prompt_evidence(evidence_files,max_bytes = max_input_bytes)
prompt <- build_prompt(role,context,task,
  evidence = paste(evidence_text,file_evidence,sep = "\n\n"),
  constraints = constraints,output_format = output_format,success_criteria = success_criteria)
cat(prompt,"\n")

# Optional API call ==========================================================
# Credentials are read from the private file only when submission is enabled.
if(send_to_api) {
  if(!exists("key",envir = .einfra,inherits = FALSE)) set_api_key(credentials_file)
  answer <- ask_llm(prompt = prompt,model = model,output_dir = paths$output_dir,
    approved_prompt = prompt,send = TRUE,max_tokens = max_tokens,
    reasoning_effort = reasoning_effort,max_input_bytes = max_input_bytes)
  cat(answer$text,"\n")
  print(answer$run_dir)
}
