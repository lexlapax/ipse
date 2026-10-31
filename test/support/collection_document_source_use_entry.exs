Code.require_file("test/test_helper.exs")
{:ok, _} = Application.ensure_all_started(:ipse)
Code.require_file("test/support/collection_document_source_use_suite.exs")
