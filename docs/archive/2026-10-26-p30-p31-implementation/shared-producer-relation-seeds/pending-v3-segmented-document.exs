%{
  "claim_commit_action" => %{
    "outcome" => %{
      "status" => "ok",
      "value" => %{
        "operation_id" => "0000000000000000000000000000006B",
        "request_sha256" => "54af8202fb94cf0189f6cae2cfd17edbcb51a11d1b12072b6031e0f4ba290b44",
        "result" => %{
          "floor" => 11,
          "generation" => 1011,
          "request_sha256" => "b4d185f187e0e199ffbc01c0f67d72bc00be4379dbecd96557d17140b3cfcd3e"
        },
        "version" => 1
      }
    },
    "request" => %{
      "op" => "collection.store",
      "request" => %{
        "generation" => 1010,
        "op" => "commit",
        "stages" => [
          %{"epoch" => "4f4db5a07c45aa01bc34cf300101ab00", "slot" => 0}
        ]
      },
      "scope" => "project"
    }
  },
  "document_metadata" => %{
    "extraction_version" => "ipse-documents-v11",
    "format" => "docx",
    "kind" => "document_extraction",
    "original_bytes" => 981,
    "original_sha256" => "aae60b32307a6985b53cbc5aec8afd34a14ed47a146decfa62aa9201ac769789",
    "segments" => [
      %{
        "end_byte" => 15,
        "locator" => %{
          "kind" => "paragraph",
          "paragraph" => 1,
          "part" => "word/document.xml"
        },
        "start_byte" => 0,
        "text_sha256" => "4b3bab2d4d4b9280723ecb5656b9b76c1d07819383320d15aa6ce00e1bbc176b"
      },
      %{
        "end_byte" => 45,
        "locator" => %{
          "kind" => "paragraph",
          "paragraph" => 2,
          "part" => "word/document.xml"
        },
        "start_byte" => 16,
        "text_sha256" => "a0ceb62294264290d3343503f07042572e0c99b5e95b317a6115c8f2208afbe3"
      },
      %{
        "end_byte" => 61,
        "locator" => %{
          "kind" => "paragraph",
          "paragraph" => 3,
          "part" => "word/document.xml"
        },
        "start_byte" => 46,
        "text_sha256" => "3b4379b82d30e47715d9cb8ca2260f7f56f96ac81ecbe004d265f04f308754d3"
      }
    ],
    "status" => "complete",
    "version" => 1,
    "warnings" => []
  },
  "document_sha256" => "aae60b32307a6985b53cbc5aec8afd34a14ed47a146decfa62aa9201ac769789",
  "embedding_request" => %{
    "expected_selection_sha256" => "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "inputs" => ["First paragraph", "保持 exact second paragraph"],
    "op" => "embedding.create",
    "profile" => "encoder",
    "timeout_ms" => 120000,
    "version" => 2
  },
  "fixture_case" => "extracted_docx_short_paragraphs",
  "generation" => 1011,
  "guard" => %{
    "batch_index" => 0,
    "claim_key" => "genproducer.notes",
    "claim_revision" => 1011,
    "claim_sha256" => "b15dd18d511dfdc3b07ac25a72fc8537f8c36a3e04776a8250ebe368090528c2",
    "version" => 1
  },
  "inputs" => ["First paragraph", "保持 exact second paragraph"],
  "kind" => "closed_model_pending_v3_no_native_history_or_inference",
  "original_docx_base64" => "UEsDBBQAAAAIAAAAIVyvV7cUiAAAAPIAAAALABwAX3JlbHMvLnJlbHNVVAkAA4ApVmmAKVZpdXgLAAEEAAAAAAQAAAAAjc89DgIhEAXgq5A5wM7GwsIAlY2t8QITGFji8hPAqLeXwmI1FpYzb/K9jDzzSj3k1JZQmnjENTUFS+/lgNjMwpHalAunkbhcI/UxVo+FzJU8426e91i3Bmi5NcXJKogUEojLs/A/dnYuGD5mc4uc+o+Kr4shU/XcFdxztWjf62mwgFrix4v6BVBLAwQUAAAACAAAACFcdCScU7sAAAA+AQAAEwAcAFtDb250ZW50X1R5cGVzXS54bWxVVAkAA4ApVmmAKVZpdXgLAAEEAAAAAAQAAAAAlZC5DsIwDIZfpcqKqBEDA2q7ACsw8AJW6rYRuRS7HG9PyjWwMdr/8VmuTvdIXNyc9VyrQSSuAVgP5JDLEMlnpQvJoeQx9RBRn7EnWC4WK9DBC3mZy9ShmmpLHY5Wit0tr9kEX6tEllWxeRknVq0wRms0Stbh4tsfyvxNKHPy6eHBRJ5lg4KmOlwoJdNSccQke3S5Dq4htdAGPbqMKCfjX7zQdUbTNz+1xRQ0MRvfO1t+FYfGf+6A59uaB1BLAwQUAAAACAAAACFchHJXsZ4AAAAPAQAAEQAcAHdvcmQvZG9jdW1lbnQueG1sVVQJAAOAKVZpgClWaXV4CwABBAAAAAAEAAAAAJWQQQrCMBBFrxJ6AKe4cBFql57AC4xJbAJNMkwiaZfuvYJn8TLiOWwEEVwIbt5n/v8Dw3RF6qhO3oQsJj+GJMu2sTmTBEjKGo9pFcmEJTtG9piXkQcokTVxVCYlFwY/wrptN+DRhabvijxEPVelCq7I/c5xyoKQcWAk20E1K/lF+u7fb9fH5SzMhCqLZFQM+o/tvXX8uw/vM+Hzgv4JUEsBAj0DFAAAAAgAAAAhXK9XtxSIAAAA8gAAAAsAGAAAAAAAAAAAAKQBAAAAAF9yZWxzLy5yZWxzVVQFAAGAKVZpdXgLAAEEAAAAAAQAAAAAUEsBAj0DFAAAAAgAAAAhXHQknFO7AAAAPgEAABMAGAAAAAAAAAAAAKQBzQAAAFtDb250ZW50X1R5cGVzXS54bWxVVAUAAYApVml1eAsAAQQAAAAABAAAAABQSwECPQMUAAAACAAAACFchHJXsZ4AAAAPAQAAEQAYAAAAAAAAAAAApAHVAQAAd29yZC9kb2N1bWVudC54bWxVVAUAAYApVml1eAsAAQQAAAAABAAAAABQSwUGAAAAAAMAAwABAQAAvgIAAAAA",
  "paragraphs" => ["First paragraph", "保持 exact second paragraph",
   "Third paragraph"],
  "profile" => %{
    "kind" => "collection",
    "partition" => "notes",
    "scope" => "project"
  },
  "records" => %{
    "catalog.notes" => %{
      "byte_count" => 259,
      "key" => "catalog.notes",
      "operation_id" => nil,
      "revision" => 1009,
      "sha256" => "ab753d13080560c708e7d4ee2c49fdcad47f59f7b8f187c31e2602347abc1b45",
      "value" => %{
        "assertions" => 0,
        "chunks" => 3,
        "entities" => 0,
        "extracted_bytes" => 61,
        "floor" => 0,
        "generation" => 1,
        "kind" => "catalog",
        "pages" => [
          %{
            "key" => "catalog.notes.0",
            "sha256" => "6adea0c84e180d762a98db2d8c1f28384c5bc0ac51ca8188b1961ff77557b06b"
          }
        ],
        "partition" => "notes",
        "sources" => 1,
        "version" => 1
      }
    },
    "catalog.notes.0" => %{
      "byte_count" => 239,
      "key" => "catalog.notes.0",
      "operation_id" => nil,
      "revision" => 1006,
      "sha256" => "6adea0c84e180d762a98db2d8c1f28384c5bc0ac51ca8188b1961ff77557b06b",
      "value" => %{
        "kind" => "catalog_page",
        "ordinal" => 0,
        "partition" => "notes",
        "rows" => [
          %{
            "head_sha256" => "b7bf4dd3fffa25e4a559630cfec7bcfd45a802e1a4f3e42eeb0a1156f1527250",
            "source_key" => "591de38170f12b36a57092d08e9b13f8de1b25c8405c857b5343796f0febafdd"
          }
        ],
        "version" => 1
      }
    },
    "data.notes.54d4ce18b9f3d5d7bf1d7578587be815f77ffcce836214510dbf35cc7d75ed8b" => %{
      "byte_count" => 1013,
      "key" => "data.notes.54d4ce18b9f3d5d7bf1d7578587be815f77ffcce836214510dbf35cc7d75ed8b",
      "operation_id" => nil,
      "revision" => 1002,
      "sha256" => "54d4ce18b9f3d5d7bf1d7578587be815f77ffcce836214510dbf35cc7d75ed8b",
      "value" => %{
        "bundle_sha256" => "20ae42c73609f7e5eaa1c6c511758f26e45b4d5ab3c8fbbe2699420fa6f36ea2",
        "kind" => "source_lexical",
        "ordinal" => 0,
        "pieces" => ["{\"chunking\":{\"max_bytes\":4096,\"version\":2},\"chunks\":[[\"f34f2da0a2ac777370335cae8d203998e1150492368246e584d8d0a18fef0f80\",0,15,2],[\"0b0a34116298515b6878742f402489520d368e16223b6606bedd889fdac974d8\",16,45,4],[\"c7d7bbf6c6efdf65342b959dcf116b0cd086fa12e808d7f5d301a7a8f6be6ccc\",46,61,2]],\"content_sha256\":\"ac1776d45e59bc64a11c1eea13a840de76e4fdecb9479e2e36eba3b768fc4843\",\"generation\":1,\"recipe\":\"ipse.evidence.word_tokens.v1\",\"selection\":{\"expires_at_ms\":null,\"historical\":false,\"observed_at_ms\":10},\"source_key\":\"591de38170f12b36a57092d08e9b13f8de1b25c8405c857b5343796f0febafdd\",\"terms\":[[\"exact\",[[1,1]]],[\"first\",[[0,1]]],[\"paragraph\",[[0,1],[1,1],[2,1]]],[\"second\",[[1,1]]],[\"third\",[[2,1]]],[\"保持\",[[1,1]]]],\"version\":2}"],
        "source_bundle_sha256" => "604e790b2f46901247e0f21507b2c77735d3bcbbef7d969c5c58a5f1bfa46eee",
        "version" => 1
      }
    },
    "data.notes.71dd59a32660fa08bf03d10ca829a1ecc17608c77a9ef6d9a41c7ca9704e175b" => %{
      "byte_count" => 2013,
      "key" => "data.notes.71dd59a32660fa08bf03d10ca829a1ecc17608c77a9ef6d9a41c7ca9704e175b",
      "operation_id" => nil,
      "revision" => 1001,
      "sha256" => "71dd59a32660fa08bf03d10ca829a1ecc17608c77a9ef6d9a41c7ca9704e175b",
      "value" => %{
        "bundle_sha256" => "604e790b2f46901247e0f21507b2c77735d3bcbbef7d969c5c58a5f1bfa46eee",
        "kind" => "source_data",
        "ordinal" => 0,
        "pieces" => ["{\"chunking\":{\"max_bytes\":4096,\"version\":2},\"content_sha256\":\"ac1776d45e59bc64a11c1eea13a840de76e4fdecb9479e2e36eba3b768fc4843\",\"event_at_ms\":null,\"expires_at_ms\":null,\"generation\":1,\"observed_at_ms\":10,\"origin\":{\"historical\":false,\"kind\":\"provided\",\"partition_or_scope\":\"notes\",\"receipt\":{\"document\":\"{\\\"extraction_version\\\":\\\"ipse-documents-v11\\\",\\\"format\\\":\\\"docx\\\",\\\"kind\\\":\\\"document_extraction\\\",\\\"original_bytes\\\":981,\\\"original_sha256\\\":\\\"aae60b32307a6985b53cbc5aec8afd34a14ed47a146decfa62aa9201ac769789\\\",\\\"segments\\\":[{\\\"end_byte\\\":15,\\\"locator\\\":{\\\"kind\\\":\\\"paragraph\\\",\\\"paragraph\\\":1,\\\"part\\\":\\\"word/document.xml\\\"},\\\"start_byte\\\":0,\\\"text_sha256\\\":\\\"4b3bab2d4d4b9280723ecb5656b9b76c1d07819383320d15aa6ce00e1bbc176b\\\"},{\\\"end_byte\\\":45,\\\"locator\\\":{\\\"kind\\\":\\\"paragraph\\\",\\\"paragraph\\\":2,\\\"part\\\":\\\"word/document.xml\\\"},\\\"start_byte\\\":16,\\\"text_sha256\\\":\\\"a0ceb62294264290d3343503f07042572e0c99b5e95b317a6115c8f2208afbe3\\\"},{\\\"end_byte\\\":61,\\\"locator\\\":{\\\"kind\\\":\\\"paragraph\\\",\\\"paragraph\\\":3,\\\"part\\\":\\\"word/document.xml\\\"},\\\"start_byte\\\":46,\\\"text_sha256\\\":\\\"3b4379b82d30e47715d9cb8ca2260f7f56f96ac81ecbe004d265f04f308754d3\\\"}],\\\"status\\\":\\\"complete\\\",\\\"version\\\":1,\\\"warnings\\\":[]}\",\"kind\":\"document_extraction\",\"sha256\":\"cb8e376f306e2f781d9de73d4bcfd4581b61a12f4b341556fed785892938e578\",\"version\":3},\"store_profile\":\"local\"},\"partition\":\"notes\",\"source_id\":\"fixture:segmented-docx\",\"source_key\":\"591de38170f12b36a57092d08e9b13f8de1b25c8405c857b5343796f0febafdd\",\"text\":\"First paragraph\\n保持 exact second paragraph\\nThird paragraph\",\"title\":\"Producer fixture\",\"uri\":\"provided:producer\",\"version\":3}"],
        "version" => 2
      }
    },
    "genjob.notes" => %{
      "byte_count" => 820,
      "key" => "genjob.notes",
      "operation_id" => nil,
      "revision" => 1009,
      "sha256" => "d169cb6ee2681209ccca3c8ed22f0827e1db8b94a56b2baef02112105d8a2fed",
      "value" => %{
        "catalog" => %{
          "assertions" => 0,
          "chunks" => 3,
          "entities" => 0,
          "extracted_bytes" => 61,
          "floor" => 0,
          "generation" => 1,
          "kind" => "catalog",
          "pages" => [
            %{
              "key" => "catalog.notes.0",
              "sha256" => "6adea0c84e180d762a98db2d8c1f28384c5bc0ac51ca8188b1961ff77557b06b"
            }
          ],
          "partition" => "notes",
          "sources" => 1,
          "version" => 1
        },
        "catalog_sha256" => "ab753d13080560c708e7d4ee2c49fdcad47f59f7b8f187c31e2602347abc1b45",
        "cursor" => 0,
        "fact_selection" => %{
          "kind" => "explicit",
          "profile" => nil,
          "version" => 1
        },
        "facts" => 0,
        "generation" => 1,
        "id" => "dd42247fbafe40a74615b208c1e33446",
        "kind" => "shared_generation_job",
        "partition" => "notes",
        "root_revision" => 0,
        "root_sha256" => nil,
        "status" => "groups",
        "summaries" => [],
        "vector_selection" => %{
          "dimensions" => 1024,
          "encoding" => "float32le",
          "model" => "fixture-model",
          "profile" => "encoder",
          "selection_sha256" => "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        "version" => 1
      }
    },
    "genproducer.notes" => %{
      "byte_count" => 1829,
      "key" => "genproducer.notes",
      "operation_id" => "0000000000000000000000000000006B",
      "revision" => 1011,
      "sha256" => "b15dd18d511dfdc3b07ac25a72fc8537f8c36a3e04776a8250ebe368090528c2",
      "value" => %{
        "catalog_floor" => 0,
        "catalog_sha256" => "ab753d13080560c708e7d4ee2c49fdcad47f59f7b8f187c31e2602347abc1b45",
        "cursor" => 0,
        "embedding" => "learned",
        "fact_selection" => %{
          "kind" => "explicit",
          "profile" => nil,
          "version" => 1
        },
        "inputs" => [
          [0, 0,
           "f34f2da0a2ac777370335cae8d203998e1150492368246e584d8d0a18fef0f80",
           "1dc1f0dbd93d5981edace24930f84fc8a6f5f41c4ab273c9acd8bac50e1ff33c",
           "4b3bab2d4d4b9280723ecb5656b9b76c1d07819383320d15aa6ce00e1bbc176b",
           0, 15],
          [0, 1,
           "0b0a34116298515b6878742f402489520d368e16223b6606bedd889fdac974d8",
           "893d9d107779900acdaf2dd309e9e2b05ac7bc8f4ead9fc6d0d2a4e2701cb41f",
           "a0ceb62294264290d3343503f07042572e0c99b5e95b317a6115c8f2208afbe3",
           16, 45],
          [0, 2,
           "c7d7bbf6c6efdf65342b959dcf116b0cd086fa12e808d7f5d301a7a8f6be6ccc",
           "dcf74808c74793c069c4835e84ff5773ac815727af55c4bb6419bb33152ccc02",
           "3b4379b82d30e47715d9cb8ca2260f7f56f96ac81ecbe004d265f04f308754d3",
           46, 61]
        ],
        "job_id" => "dd42247fbafe40a74615b208c1e33446",
        "job_revision" => 1009,
        "kind" => "shared_projection_producer",
        "page" => nil,
        "partition" => "notes",
        "receipts" => [],
        "recipe" => "ipse.evidence.shared_producer.first_page.v3",
        "root_revision" => 0,
        "root_sha256" => nil,
        "source_bindings" => [
          %{
            "bundle_sha256" => "604e790b2f46901247e0f21507b2c77735d3bcbbef7d969c5c58a5f1bfa46eee",
            "chunking_sha256" => "3ad0057e6e8e71cc9c3d74dd9adf24e7854b603dfa1d19328969a6600020c73c",
            "expires_at_ms" => nil,
            "head_revision" => 1006,
            "head_sha256" => "b7bf4dd3fffa25e4a559630cfec7bcfd45a802e1a4f3e42eeb0a1156f1527250",
            "historical" => false,
            "observed_at_ms" => 10,
            "source_key" => "591de38170f12b36a57092d08e9b13f8de1b25c8405c857b5343796f0febafdd"
          }
        ],
        "source_set_sha256" => "f039598daa53e6f710464f43b00feef514fe881dbf6434a2a3eae86e5d772482",
        "status" => "pending",
        "vector_selection" => %{
          "dimensions" => 1024,
          "encoding" => "float32le",
          "model" => "fixture-model",
          "profile" => "encoder",
          "selection_sha256" => "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        "version" => 3
      }
    },
    "source.notes.591de38170f12b36a57092d08e9b13f8de1b25c8405c857b5343796f0febafdd" => %{
      "byte_count" => 876,
      "key" => "source.notes.591de38170f12b36a57092d08e9b13f8de1b25c8405c857b5343796f0febafdd",
      "operation_id" => nil,
      "revision" => 1006,
      "sha256" => "b7bf4dd3fffa25e4a559630cfec7bcfd45a802e1a4f3e42eeb0a1156f1527250",
      "value" => %{
        "blocks" => [
          %{
            "key" => "data.notes.71dd59a32660fa08bf03d10ca829a1ecc17608c77a9ef6d9a41c7ca9704e175b",
            "sha256" => "71dd59a32660fa08bf03d10ca829a1ecc17608c77a9ef6d9a41c7ca9704e175b"
          }
        ],
        "bundle_sha256" => "604e790b2f46901247e0f21507b2c77735d3bcbbef7d969c5c58a5f1bfa46eee",
        "byte_count" => 1616,
        "chunks" => 3,
        "generation" => 1,
        "kind" => "source_head",
        "lexical" => %{
          "blocks" => [
            %{
              "key" => "data.notes.54d4ce18b9f3d5d7bf1d7578587be815f77ffcce836214510dbf35cc7d75ed8b",
              "sha256" => "54d4ce18b9f3d5d7bf1d7578587be815f77ffcce836214510dbf35cc7d75ed8b"
            }
          ],
          "bundle_sha256" => "20ae42c73609f7e5eaa1c6c511758f26e45b4d5ab3c8fbbe2699420fa6f36ea2",
          "byte_count" => 725,
          "content_sha256" => "ac1776d45e59bc64a11c1eea13a840de76e4fdecb9479e2e36eba3b768fc4843",
          "recipe" => "ipse.evidence.word_tokens.v1",
          "version" => 1
        },
        "ordinal" => 0,
        "revision" => 1,
        "source_key" => "591de38170f12b36a57092d08e9b13f8de1b25c8405c857b5343796f0febafdd",
        "text_bytes" => 61,
        "version" => 2
      }
    }
  },
  "selection" => %{
    "dimensions" => 1024,
    "encoding" => "float32le",
    "model" => "fixture-model",
    "profile" => "encoder",
    "selection_sha256" => "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  },
  "source_policy" => %{
    "expires_at_ms" => nil,
    "historical" => false,
    "observed_at_ms" => 10
  }
}
