Code.require_file("../../support/provider_conformance.ex", __DIR__)

defmodule Ipse.Provider.GeminiConformanceTest do
  use ExUnit.Case, async: false

  use Ipse.Test.ProviderConformance,
    provider: :gemini,
    adapter: Ipse.Provider.Gemini,
    events: Ipse.Test.ProviderConformance.Gemini
end

defmodule Ipse.Provider.OpenAIConformanceTest do
  use ExUnit.Case, async: false

  use Ipse.Test.ProviderConformance,
    provider: :openai,
    adapter: Ipse.Provider.OpenAI,
    events: Ipse.Test.ProviderConformance.OpenAI
end

defmodule Ipse.Provider.AnthropicConformanceTest do
  use ExUnit.Case, async: false

  use Ipse.Test.ProviderConformance,
    provider: :anthropic,
    adapter: Ipse.Provider.Anthropic,
    events: Ipse.Test.ProviderConformance.Anthropic
end

defmodule Ipse.Provider.OllamaConformanceTest do
  use ExUnit.Case, async: false

  use Ipse.Test.ProviderConformance,
    provider: :ollama,
    adapter: Ipse.Provider.Ollama,
    events: Ipse.Test.ProviderConformance.Ollama
end

defmodule Ipse.Provider.OpenRouterConformanceTest do
  use ExUnit.Case, async: false

  use Ipse.Test.ProviderConformance,
    provider: :openrouter,
    adapter: Ipse.Provider.ChatCompletions,
    events: Ipse.Test.ProviderConformance.OpenRouter
end

defmodule Ipse.Provider.LocalCompatibleConformanceTest do
  use ExUnit.Case, async: false

  use Ipse.Test.ProviderConformance,
    provider: :openai_compatible,
    adapter: Ipse.Provider.ChatCompletions,
    events: Ipse.Test.ProviderConformance.ChatCompletions
end
