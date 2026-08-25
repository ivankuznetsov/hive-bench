# Extend the Sol judge bound under parallel load

- Raised the finite GPT-5.6 Sol CLI judge timeout from 1,800 to 3,600 seconds.
- A live ultra-reasoning sample reached the old ceiling while generation and
  judging were fully parallel; the associated cell and all three Fable samples
  were already valid, so missing Sol samples can be backfilled without
  regenerating the candidate.
