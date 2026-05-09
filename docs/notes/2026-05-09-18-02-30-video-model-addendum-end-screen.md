# Addendum to video-model-youtube-api note

End Screen should be included in the pre-publish checklist alongside game, age restriction (18+), and paid promotion. Same rationale: the YouTube Data API v3 has no read or write surface for end screens, so the user has to confirm it out-of-band in Studio before we flip a video to public or schedule it.

Updated checklist:

- [ ] Game set correctly (if category = Gaming)
- [ ] Age restriction (18+) reviewed
- [ ] Paid promotion declared if applicable
- [ ] End screen reviewed

Studio deep link pattern is the same: `https://studio.youtube.com/video/{videoId}/edit`.
