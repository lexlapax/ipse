> Historical snapshot, archived 2026-10-14 from commit `27fbf6d`. Original path: `docs/naming.md`.
> Superseded guidance; use the [current documentation map](../../../index.md).

# Why Ipse

**Ipse** names the idea of a self maintained through an ongoing loop. The name
draws on Latin and on Douglas Hofstadter's *I Am a Strange Loop*. It is a word,
not an acronym.

## The word

Latin *ipse* belongs to the intensive pronoun *ipse, ipsa, ipsum*: it emphasizes
the person or thing itself, as in “he himself” or “the very thing.” It is not
the Latin word for “I” (*ego*), nor does it literally mean “loop.” See
[Lewis and Short via Logeion](https://logeion.uchicago.edu/ipse) and
[Allen and Greenough, pronoun syntax](https://www.perseus.tufts.edu/hopper/text?doc=Perseus%3Atext%3A1999.04.0001%3Apart%3D2%3Asection%3D4).

The related English word *ipseity* means individuality or selfhood:
[Dictionary.com](https://www.dictionary.com/browse/ipseity). This is a plausible
memory cue for the earlier naming research, whose original notes have not been
recovered.

## The Hofstadter connection

In *I Am a Strange Loop*, Hofstadter investigates how the “I” arises from
self-referential patterns. The account involves interaction between levels:
physical activity supports symbols, while the symbolic level participates in
feedback that guides activity. The publisher's
[description of the book](https://www.hachettebookgroup.com/titles/douglas-r-hofstadter/i-am-a-strange-loop/9780465030798/?lens=basic-books)
sets out this relationship between the “I,” symbols, and physical processes.

The naming connection is therefore **strange loop → selfhood → ipse**. It is an
interpretation connecting the book to the Latin word. The research did not
establish that Hofstadter coined this name or used *ipse* as a technical term
in the book. An ordinary feedback loop alone is not the full philosophical
claim of a strange loop.

Another possible memory cue is Paul Ricoeur's distinction between *idem*
(sameness) and *ipse* (selfhood across change), discussed in the
[Stanford Encyclopedia of Philosophy](https://plato.stanford.edu/archives/fall2016/entries/ricoeur/).
That is a separate philosophical connection, not an attribution to Hofstadter.

## What the name means for this project

The software has a concrete feedback cycle: receive a task, choose an action,
observe the result, record it, and use that context to choose the next action.
Its journal lets a session retain continuity across interruptions. Skills can
provide additional instructions without prescribing one fixed workflow.

This gives the name an engineering interpretation: **continuity through
recorded experience and feedback**. The name makes no claim about machine
consciousness and does not require a self-modifying or philosophically faithful
implementation of Hofstadter's theory.

| Surface | Name |
| --- | --- |
| Project | Ipse |
| Repository | `lexlapax/ipse` |
| Command | `ipse` |
| Elixir namespace | `Ipse` |
| OTP application and event tag | `:ipse` |
| Environment variables | `IPSE_*` |
| Default local data | `~/.ipse` |
| Native helper | `ipse-runner` |

The public description stays practical: **an Elixir-native coding agent with
local skills and resumable conversations**. The philosophical origin belongs
in this note, while everyday usage should remain straightforward.
