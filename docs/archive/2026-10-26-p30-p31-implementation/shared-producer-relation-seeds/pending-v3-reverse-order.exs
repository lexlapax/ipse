%{
  "claim_commit_action" => %{
    "outcome" => %{
      "status" => "ok",
      "value" => %{
        "operation_id" => "000000000000000000000000000000B2",
        "request_sha256" => "75cb41ef643c0a91c66f7aed67ecc9f93fd92db4a4afc89658e6db07cf74eee7",
        "result" => %{
          "floor" => 17,
          "generation" => 1017,
          "request_sha256" => "a799d978e8a29a7dc48c2604f4d992ba58ee9aa68865e9d3cdb332d70147a944"
        },
        "version" => 1
      }
    },
    "request" => %{
      "op" => "collection.store",
      "request" => %{
        "generation" => 1016,
        "op" => "commit",
        "stages" => [
          %{"epoch" => "55ce4b469fef0950fd376a3ca46b0abf", "slot" => 0}
        ]
      },
      "scope" => "project"
    }
  },
  "embedding_request" => %{
    "expected_selection_sha256" => "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "inputs" => ["reverse insertion source fixture:reverse-two",
     "reverse insertion source fixture:reverse-one"],
    "op" => "embedding.create",
    "profile" => "encoder",
    "timeout_ms" => 120000,
    "version" => 2
  },
  "fixture_case" => "reverse_insertion_sorted_catalog",
  "generation" => 1017,
  "guard" => %{
    "batch_index" => 0,
    "claim_key" => "genproducer.notes",
    "claim_revision" => 1017,
    "claim_sha256" => "1426a03f80793b2215d71b3ada23476caac143d0e458aed8f9f2bccfb28df9f6",
    "version" => 1
  },
  "head_ordinals_in_claim_order" => [1, 0],
  "inputs" => ["reverse insertion source fixture:reverse-two",
   "reverse insertion source fixture:reverse-one"],
  "inserted_source_ids" => ["fixture:reverse-one", "fixture:reverse-two"],
  "kind" => "closed_model_pending_v3_no_native_history_or_inference",
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
      "revision" => 1015,
      "sha256" => "bd2825797e7f6064347399be2892f55db93943642a7f349adcb82a7eeffdaa6d",
      "value" => %{
        "assertions" => 0,
        "chunks" => 2,
        "entities" => 0,
        "extracted_bytes" => 88,
        "floor" => 0,
        "generation" => 2,
        "kind" => "catalog",
        "pages" => [
          %{
            "key" => "catalog.notes.0",
            "sha256" => "3b7bf73a47206f9dede31a3918c75b627a3d752789ee3b9cc80128a1d1c1bc87"
          }
        ],
        "partition" => "notes",
        "sources" => 2,
        "version" => 1
      }
    },
    "catalog.notes.0" => %{
      "byte_count" => 402,
      "key" => "catalog.notes.0",
      "operation_id" => nil,
      "revision" => 1012,
      "sha256" => "3b7bf73a47206f9dede31a3918c75b627a3d752789ee3b9cc80128a1d1c1bc87",
      "value" => %{
        "kind" => "catalog_page",
        "ordinal" => 0,
        "partition" => "notes",
        "rows" => [
          %{
            "head_sha256" => "fff9e0ec3c7380665644fe017f33ab9997a99052b13e35d2410a48769b7a7ae3",
            "source_key" => "82c0c08f8c6aacade064d99dbe376c154066a8eacb65396204a2ee27172c963c"
          },
          %{
            "head_sha256" => "13423bc7fbff3666658d91c1b51141908e9f64483edf6c5150d8ca76500fa205",
            "source_key" => "e55e750291dbf7fa5a49bf47e964280384309d1029d8d7b02277e7f65d90b59a"
          }
        ],
        "version" => 1
      }
    },
    "data.notes.5d76f565bbd5ffea240fcbcbed2a4cd4b584ffb8bedc5be8aff3b3e583c8defa" => %{
      "byte_count" => 824,
      "key" => "data.notes.5d76f565bbd5ffea240fcbcbed2a4cd4b584ffb8bedc5be8aff3b3e583c8defa",
      "operation_id" => nil,
      "revision" => 1008,
      "sha256" => "5d76f565bbd5ffea240fcbcbed2a4cd4b584ffb8bedc5be8aff3b3e583c8defa",
      "value" => %{
        "bundle_sha256" => "4369680bb54c64534a3989c53adbd9fa483a850d8e589259e4797d7223c288c0",
        "kind" => "source_lexical",
        "ordinal" => 0,
        "pieces" => ["{\"chunking\":{\"max_bytes\":4096,\"version\":2},\"chunks\":[[\"7e02c60cda9e4adcd1b8d7a774338234513c8895b4a9813a4ef1bf338aa93c8f\",0,44,6]],\"content_sha256\":\"2298e5c47896e74af3968efd09b81c157671cec35e6648f86db4c68a24a020af\",\"generation\":1,\"recipe\":\"ipse.evidence.word_tokens.v1\",\"selection\":{\"expires_at_ms\":null,\"historical\":false,\"observed_at_ms\":10},\"source_key\":\"82c0c08f8c6aacade064d99dbe376c154066a8eacb65396204a2ee27172c963c\",\"terms\":[[\"fixture\",[[0,1]]],[\"insertion\",[[0,1]]],[\"reverse\",[[0,2]]],[\"source\",[[0,1]]],[\"two\",[[0,1]]]],\"version\":2}"],
        "source_bundle_sha256" => "09c5f5c10362c10afd4c668238b5397adb19807678cbb03077bbba81814c9856",
        "version" => 1
      }
    },
    "data.notes.945714acb342722e1f6929d9eefdc761223a0bb060ec250af005a21c2a7efb92" => %{
      "byte_count" => 776,
      "key" => "data.notes.945714acb342722e1f6929d9eefdc761223a0bb060ec250af005a21c2a7efb92",
      "operation_id" => nil,
      "revision" => 1001,
      "sha256" => "945714acb342722e1f6929d9eefdc761223a0bb060ec250af005a21c2a7efb92",
      "value" => %{
        "bundle_sha256" => "d37b0ff9005b5c6e81f4f9f395f13a62d92825c9e8c83fdcf5e0b32fd930a185",
        "kind" => "source_data",
        "ordinal" => 0,
        "pieces" => ["{\"chunking\":{\"max_bytes\":4096,\"version\":2},\"content_sha256\":\"d852a4eda4ac541c3ab94e23ce29ef223321f6c89a04da38a4063551813fcc12\",\"event_at_ms\":null,\"expires_at_ms\":null,\"generation\":1,\"observed_at_ms\":10,\"origin\":{\"historical\":false,\"kind\":\"provided\",\"partition_or_scope\":\"notes\",\"receipt\":null,\"store_profile\":\"local\"},\"partition\":\"notes\",\"source_id\":\"fixture:reverse-one\",\"source_key\":\"e55e750291dbf7fa5a49bf47e964280384309d1029d8d7b02277e7f65d90b59a\",\"text\":\"reverse insertion source fixture:reverse-one\",\"title\":\"Producer fixture\",\"uri\":\"provided:producer\",\"version\":3}"],
        "version" => 2
      }
    },
    "data.notes.c1bf77b26e421dfe5b234fb56863a2d751bb87d1d09d2b25842fb9e87f68cc7b" => %{
      "byte_count" => 776,
      "key" => "data.notes.c1bf77b26e421dfe5b234fb56863a2d751bb87d1d09d2b25842fb9e87f68cc7b",
      "operation_id" => nil,
      "revision" => 1007,
      "sha256" => "c1bf77b26e421dfe5b234fb56863a2d751bb87d1d09d2b25842fb9e87f68cc7b",
      "value" => %{
        "bundle_sha256" => "09c5f5c10362c10afd4c668238b5397adb19807678cbb03077bbba81814c9856",
        "kind" => "source_data",
        "ordinal" => 0,
        "pieces" => ["{\"chunking\":{\"max_bytes\":4096,\"version\":2},\"content_sha256\":\"2298e5c47896e74af3968efd09b81c157671cec35e6648f86db4c68a24a020af\",\"event_at_ms\":null,\"expires_at_ms\":null,\"generation\":1,\"observed_at_ms\":10,\"origin\":{\"historical\":false,\"kind\":\"provided\",\"partition_or_scope\":\"notes\",\"receipt\":null,\"store_profile\":\"local\"},\"partition\":\"notes\",\"source_id\":\"fixture:reverse-two\",\"source_key\":\"82c0c08f8c6aacade064d99dbe376c154066a8eacb65396204a2ee27172c963c\",\"text\":\"reverse insertion source fixture:reverse-two\",\"title\":\"Producer fixture\",\"uri\":\"provided:producer\",\"version\":3}"],
        "version" => 2
      }
    },
    "data.notes.e50a0188e9b8d17fbc0612d08572f06ed1aa1a748f5a1d4f7fa310f61641c518" => %{
      "byte_count" => 824,
      "key" => "data.notes.e50a0188e9b8d17fbc0612d08572f06ed1aa1a748f5a1d4f7fa310f61641c518",
      "operation_id" => nil,
      "revision" => 1002,
      "sha256" => "e50a0188e9b8d17fbc0612d08572f06ed1aa1a748f5a1d4f7fa310f61641c518",
      "value" => %{
        "bundle_sha256" => "9af469c215edc861030f703ecafdae2fe11d0362a333330ef9c7718cc1f067a3",
        "kind" => "source_lexical",
        "ordinal" => 0,
        "pieces" => ["{\"chunking\":{\"max_bytes\":4096,\"version\":2},\"chunks\":[[\"39d18758b489ed3305e966d83e4a888003a9f274ad5819b44723470f6c2c4197\",0,44,6]],\"content_sha256\":\"d852a4eda4ac541c3ab94e23ce29ef223321f6c89a04da38a4063551813fcc12\",\"generation\":1,\"recipe\":\"ipse.evidence.word_tokens.v1\",\"selection\":{\"expires_at_ms\":null,\"historical\":false,\"observed_at_ms\":10},\"source_key\":\"e55e750291dbf7fa5a49bf47e964280384309d1029d8d7b02277e7f65d90b59a\",\"terms\":[[\"fixture\",[[0,1]]],[\"insertion\",[[0,1]]],[\"one\",[[0,1]]],[\"reverse\",[[0,2]]],[\"source\",[[0,1]]]],\"version\":2}"],
        "source_bundle_sha256" => "d37b0ff9005b5c6e81f4f9f395f13a62d92825c9e8c83fdcf5e0b32fd930a185",
        "version" => 1
      }
    },
    "genjob.notes" => %{
      "byte_count" => 820,
      "key" => "genjob.notes",
      "operation_id" => nil,
      "revision" => 1015,
      "sha256" => "0da853b09f1518611a220d53421f7c5dd338a54aa970902432a035d6ca89da2b",
      "value" => %{
        "catalog" => %{
          "assertions" => 0,
          "chunks" => 2,
          "entities" => 0,
          "extracted_bytes" => 88,
          "floor" => 0,
          "generation" => 2,
          "kind" => "catalog",
          "pages" => [
            %{
              "key" => "catalog.notes.0",
              "sha256" => "3b7bf73a47206f9dede31a3918c75b627a3d752789ee3b9cc80128a1d1c1bc87"
            }
          ],
          "partition" => "notes",
          "sources" => 2,
          "version" => 1
        },
        "catalog_sha256" => "bd2825797e7f6064347399be2892f55db93943642a7f349adcb82a7eeffdaa6d",
        "cursor" => 0,
        "fact_selection" => %{
          "kind" => "explicit",
          "profile" => nil,
          "version" => 1
        },
        "facts" => 0,
        "generation" => 1,
        "id" => "5935aaa21366cb00832721f697493865",
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
      "byte_count" => 2027,
      "key" => "genproducer.notes",
      "operation_id" => "000000000000000000000000000000B2",
      "revision" => 1017,
      "sha256" => "1426a03f80793b2215d71b3ada23476caac143d0e458aed8f9f2bccfb28df9f6",
      "value" => %{
        "catalog_floor" => 0,
        "catalog_sha256" => "bd2825797e7f6064347399be2892f55db93943642a7f349adcb82a7eeffdaa6d",
        "cursor" => 0,
        "embedding" => "learned",
        "fact_selection" => %{
          "kind" => "explicit",
          "profile" => nil,
          "version" => 1
        },
        "inputs" => [
          [0, 0,
           "7e02c60cda9e4adcd1b8d7a774338234513c8895b4a9813a4ef1bf338aa93c8f",
           "a7686244536dfa5b9478a0e2933519901ca67ac5c579768e3995c91d5fe2c35a",
           "2298e5c47896e74af3968efd09b81c157671cec35e6648f86db4c68a24a020af",
           0, 44],
          [1, 0,
           "39d18758b489ed3305e966d83e4a888003a9f274ad5819b44723470f6c2c4197",
           "b7dfa94263a942271921956b1e1a2b70df19cf486efaed1706a26f56791022ce",
           "d852a4eda4ac541c3ab94e23ce29ef223321f6c89a04da38a4063551813fcc12",
           0, 44]
        ],
        "job_id" => "5935aaa21366cb00832721f697493865",
        "job_revision" => 1015,
        "kind" => "shared_projection_producer",
        "page" => nil,
        "partition" => "notes",
        "receipts" => [],
        "recipe" => "ipse.evidence.shared_producer.first_page.v3",
        "root_revision" => 0,
        "root_sha256" => nil,
        "source_bindings" => [
          %{
            "bundle_sha256" => "09c5f5c10362c10afd4c668238b5397adb19807678cbb03077bbba81814c9856",
            "chunking_sha256" => "3ad0057e6e8e71cc9c3d74dd9adf24e7854b603dfa1d19328969a6600020c73c",
            "expires_at_ms" => nil,
            "head_revision" => 1012,
            "head_sha256" => "fff9e0ec3c7380665644fe017f33ab9997a99052b13e35d2410a48769b7a7ae3",
            "historical" => false,
            "observed_at_ms" => 10,
            "source_key" => "82c0c08f8c6aacade064d99dbe376c154066a8eacb65396204a2ee27172c963c"
          },
          %{
            "bundle_sha256" => "d37b0ff9005b5c6e81f4f9f395f13a62d92825c9e8c83fdcf5e0b32fd930a185",
            "chunking_sha256" => "3ad0057e6e8e71cc9c3d74dd9adf24e7854b603dfa1d19328969a6600020c73c",
            "expires_at_ms" => nil,
            "head_revision" => 1006,
            "head_sha256" => "13423bc7fbff3666658d91c1b51141908e9f64483edf6c5150d8ca76500fa205",
            "historical" => false,
            "observed_at_ms" => 10,
            "source_key" => "e55e750291dbf7fa5a49bf47e964280384309d1029d8d7b02277e7f65d90b59a"
          }
        ],
        "source_set_sha256" => "c2cf7111ef695b387136cd8c7c3bf18256ac71d616864107e4cb3c1a41ceb6ba",
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
    "source.notes.82c0c08f8c6aacade064d99dbe376c154066a8eacb65396204a2ee27172c963c" => %{
      "byte_count" => 875,
      "key" => "source.notes.82c0c08f8c6aacade064d99dbe376c154066a8eacb65396204a2ee27172c963c",
      "operation_id" => nil,
      "revision" => 1012,
      "sha256" => "fff9e0ec3c7380665644fe017f33ab9997a99052b13e35d2410a48769b7a7ae3",
      "value" => %{
        "blocks" => [
          %{
            "key" => "data.notes.c1bf77b26e421dfe5b234fb56863a2d751bb87d1d09d2b25842fb9e87f68cc7b",
            "sha256" => "c1bf77b26e421dfe5b234fb56863a2d751bb87d1d09d2b25842fb9e87f68cc7b"
          }
        ],
        "bundle_sha256" => "09c5f5c10362c10afd4c668238b5397adb19807678cbb03077bbba81814c9856",
        "byte_count" => 571,
        "chunks" => 1,
        "generation" => 1,
        "kind" => "source_head",
        "lexical" => %{
          "blocks" => [
            %{
              "key" => "data.notes.5d76f565bbd5ffea240fcbcbed2a4cd4b584ffb8bedc5be8aff3b3e583c8defa",
              "sha256" => "5d76f565bbd5ffea240fcbcbed2a4cd4b584ffb8bedc5be8aff3b3e583c8defa"
            }
          ],
          "bundle_sha256" => "4369680bb54c64534a3989c53adbd9fa483a850d8e589259e4797d7223c288c0",
          "byte_count" => 542,
          "content_sha256" => "2298e5c47896e74af3968efd09b81c157671cec35e6648f86db4c68a24a020af",
          "recipe" => "ipse.evidence.word_tokens.v1",
          "version" => 1
        },
        "ordinal" => 1,
        "revision" => 1,
        "source_key" => "82c0c08f8c6aacade064d99dbe376c154066a8eacb65396204a2ee27172c963c",
        "text_bytes" => 44,
        "version" => 2
      }
    },
    "source.notes.e55e750291dbf7fa5a49bf47e964280384309d1029d8d7b02277e7f65d90b59a" => %{
      "byte_count" => 875,
      "key" => "source.notes.e55e750291dbf7fa5a49bf47e964280384309d1029d8d7b02277e7f65d90b59a",
      "operation_id" => nil,
      "revision" => 1006,
      "sha256" => "13423bc7fbff3666658d91c1b51141908e9f64483edf6c5150d8ca76500fa205",
      "value" => %{
        "blocks" => [
          %{
            "key" => "data.notes.945714acb342722e1f6929d9eefdc761223a0bb060ec250af005a21c2a7efb92",
            "sha256" => "945714acb342722e1f6929d9eefdc761223a0bb060ec250af005a21c2a7efb92"
          }
        ],
        "bundle_sha256" => "d37b0ff9005b5c6e81f4f9f395f13a62d92825c9e8c83fdcf5e0b32fd930a185",
        "byte_count" => 571,
        "chunks" => 1,
        "generation" => 1,
        "kind" => "source_head",
        "lexical" => %{
          "blocks" => [
            %{
              "key" => "data.notes.e50a0188e9b8d17fbc0612d08572f06ed1aa1a748f5a1d4f7fa310f61641c518",
              "sha256" => "e50a0188e9b8d17fbc0612d08572f06ed1aa1a748f5a1d4f7fa310f61641c518"
            }
          ],
          "bundle_sha256" => "9af469c215edc861030f703ecafdae2fe11d0362a333330ef9c7718cc1f067a3",
          "byte_count" => 542,
          "content_sha256" => "d852a4eda4ac541c3ab94e23ce29ef223321f6c89a04da38a4063551813fcc12",
          "recipe" => "ipse.evidence.word_tokens.v1",
          "version" => 1
        },
        "ordinal" => 0,
        "revision" => 1,
        "source_key" => "e55e750291dbf7fa5a49bf47e964280384309d1029d8d7b02277e7f65d90b59a",
        "text_bytes" => 44,
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
