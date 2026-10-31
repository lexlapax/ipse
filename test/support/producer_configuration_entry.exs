Code.require_file("test/test_helper.exs")
ExUnit.configure(exclude: [:test], include: [:producer_config_child])
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/extensions/knowledge/producer_configuration_test.exs")
