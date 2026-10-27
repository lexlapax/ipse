//! Bounded child-only launch environment decoding shared by OS helpers.
pub fn decode_environment(bytes: &[u8]) -> Result<Vec<(String, String)>, String> {
    fn number(input: &mut &[u8]) -> Result<usize, String> {
        if input.len() < 4 {
            return Err("invalid launch environment".into());
        }
        let value = u32::from_be_bytes(input[..4].try_into().unwrap()) as usize;
        *input = &input[4..];
        Ok(value)
    }
    fn string(input: &mut &[u8]) -> Result<String, String> {
        let size = number(input)?;
        if size > input.len() {
            return Err("invalid launch environment".into());
        }
        let text = std::str::from_utf8(&input[..size]).map_err(|_| "invalid launch environment")?;
        if text.contains('\0') {
            return Err("invalid launch environment".into());
        }
        let value = text.to_owned();
        *input = &input[size..];
        Ok(value)
    }
    if bytes.len() > 134_144 {
        return Err("launch environment exceeds limit".into());
    }
    let mut input = bytes;
    let count = number(&mut input)?;
    if count > 130 {
        return Err("launch environment exceeds limit".into());
    }
    let mut result = Vec::new();
    for _ in 0..count {
        let key = string(&mut input)?;
        let value = string(&mut input)?;
        if key.is_empty()
            || !key
                .bytes()
                .enumerate()
                .all(|(i, b)| b == b'_' || b.is_ascii_alphabetic() || (i > 0 && b.is_ascii_digit()))
            || result.iter().any(|(previous, _)| previous == &key)
        {
            return Err("invalid launch environment".into());
        }
        result.push((key, value));
    }
    if !input.is_empty() {
        return Err("invalid launch environment".into());
    }
    Ok(result)
}
