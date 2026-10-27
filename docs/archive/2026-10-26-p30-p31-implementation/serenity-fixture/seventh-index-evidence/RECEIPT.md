# Seventh Serenity retry index, 2026-10-27

The coordinator ran the independently reviewed [index-only harness](seventh_index_harness.sh), SHA-256 `4cfd884afa1f466a19879c0b8cab372fb3a845900a046dc0ad915ab9a3814270`, with nonce `23456b0d98b24adcb65d36e11a87fb83`. It reported success and created loop index 4089, host sysfs `25:820008`, container sysfs `84:820008`. The copied program's identity and hash were checked in a root-owned read-only stage before execution. No backing binding, mapper creation, block I/O or index removal was part of this operation.

Receipt parent `/home/lexlapax/projects/lexlapax/ipse/.serenity-seventh-receipt.62mbAQNi` contains ledger `29:13366395` and index receipt `29:13366657`, SHA-256 `a46a66a1ef17faf56d5d975248f96c18e259dee72a370cc8842eca02ce78365a`. Setup container `e7d73ec2af55270621d8553e98239d1e1d9ae65839307e6303bc32ca475d688c` was independently inspected as exited 0; stage `/tmp/ipse-retry-index-stage.7OTQz5hj` `53:332543`, program `53:332544`, were initially retained pending exact cleanup. Index and ledger remain; prior retained resources were untouched.

Host `/dev/loop4089` was observed as block `7:4089` device:inode `7:1641`; mapper `252:4089` was absent at that observation. This record derives from tool transcript and independent read-only inspection, not a raw output log. It is not evidence of Btrfs fault testing or kernel qualification.
