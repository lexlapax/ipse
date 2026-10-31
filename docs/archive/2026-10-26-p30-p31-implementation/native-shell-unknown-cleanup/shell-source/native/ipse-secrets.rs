// Inherited provider credentials are withheld from trusted shell execution.
// The Elixir registry conformance test checks this native boundary for every key.
pub const KEYS: &[&str] = &[
    "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "IPSE_CHATGPT_ACCESS_TOKEN",
    "OPENROUTER_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY", "XAI_API_KEY",
    "TYPESAFE_API_KEY",
];

pub fn contains(key: &[u8]) -> bool {
    KEYS.iter().any(|candidate| candidate.as_bytes() == key)
}
