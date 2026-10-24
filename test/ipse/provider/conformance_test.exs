Code.require_file("../../support/provider_conformance.ex", __DIR__)

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
