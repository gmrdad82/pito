# /games revamp brief (raw)

We're gonna do a screen polish, sweep, fat cut.

1. has horizontal scroll and has to go. We remove [search] button we search
   automatically after 5 chars written OR by hitting ENTER. This way games with
   fewer characters can be searched. - This has to be specced. [cancel] link has
   to be our component for [cancel] which is muted. add a game from igdb -> add
   a game. drop the copy "type to search igdb." - I already know this.

2. group the multiple versions of a game into the base, main game title - This
   has to be specced.

3. Adding a new game will land for a bit into Untitled game. Try fetch already
   the game title to put it in the breadcrumb.

4. we cleanup here. We keep the shelves for genre, with each genre on a shelf.
   After we have collections shelf. One shelf for all collections; display order
   is alphabetical for the collection. Same order apply to the genre when
   having multiple games on a genre shelf. Genre names should be short form
   like RPG instead of Role Playing Game.

5. When a game comes with multiple genres we keep only 1 main genre - this has
   to be specced and I think we already have this, but check it out.

6. We remove multiple display types. We keep only the default ones where we
   group games by letter. We drop grid and list. We remove the localstorage
   that we added for this. We have 2 different cover size on this page: one for
   genres and collections and one for the game listing. We'll have a shelf for
   each letter. If a letter doesn't have games we don't display them. All
   shelves have the games ordered alphabetically inside them. All shelves have
   horizontal scroll (our themed horizontal scroll) when needed. I want our
   horizontal and vertical scrolls to be revamped / visited to be slimmer -
   probably 4-6px in tickness.

7. For collection cover art we use what you already designer 2up, Netflix, 4up,
   others but I need you to explain what could go for 5 games, as for 6 I think
   we can do 3 up and 3 down, for 7 I dunno, same for 8 and I'm not sure where
   to stop and limit to make the cover art for the first X games from the
   collection.

8. Our actions from the keyboard shorcuts for Games won't have - delete and r
   resync. Remove these from the G games menu. Remove r resync from G games ->
   B bundles.

9. The 2 rows of filtering will be reworked. We move these 2 rows up, between
   title and the first genre shelf. And we have a lot of rework on the backend
   to satisfy, while keeping in mind that these filters, reflects in the URL
   bar but don't refresh the page, and we won't have any pagination on this
   /games page. The new filters will be like this:
   Left hand side: [ ] released [ ] scheduled [ ] owned [ ] purchase (this is the old not owned) [ ] played
   Right hand side: [ ] PS5 [ ] Switch 2 (check naming if it's Switch 2 or Switch2) [ ] Steam [ ] GoG [ ] Epic (we don't use Xbox)
   All these will be defaulted to checked state and the url /games would be the same as /games?filters=all but I would like th have /games if possible. When playing with filters the URL will change but will change to /games if all filters are selected, if possible.

10. If you can, maybe use the Google fav icon service or I'll search and give
    you the files, I want in the cover art for the game listing, after the
    year, to add a separator (dot) and show the platform logo for that specific
    game.

11. In the past I said something about how some of the filters work when
    combining, and this has to be specced: if I check [x] played, then this
    will imply [x] released [x] owned to be also checked and at least one of
    the platform.

12. Be sure to catch the scenario when adding a game to a bundle (collection)
    the coverart has to be regenerated, but if added multiple games to a
    collection, we should be process the compound coverart considering the
    order the games have beed added to the collection while sorting the games
    alphabetically. So adding 3 games will trigger 3 regeneration cover art
    jobs and they have to be executed in a clear order.

13. It's ok to have resync on game and bundle at item level in their page
    specifically.

14. Moving to game page - no need for edit page. Remove it entirely. [-] delete
    won't do bulk delete anymore but rather a modal confirmation with
    [delete](danger color we have or should have already a view component for
    this) and [cancel] (our viewcomponent for cancel dialog) - deleting will
    trigger collection update cover art if case.

15. ratings will be displayed here after dev: ... pub: ... as a hear bar using
    our colors that we have already for different score and you should evaluate
    somehow objectively the igdb, aggregated, total scores to produce only one
    scrore from 0 to 100. If you don't have a score you'll have the heatbar
    viewcomponent as a muted bar.

16. on the right hand side of the cover art column, basically on the 2nd pane
    you start with summary. you follow with a hairline. then you put time to
    beat as a 3 column table threated as number (aligned right), round
    everything up to h(hour) - I don't care about minutes.

17. We move genres to the left hand side between game title and released: and
    we do (bold) main genre, normal text other genres if multiple, but limit to
    3 or 4 or 5 genres in total. I trust your judgement on this pick.

18. Also here after the genres, still on the left hand side, we add the
    platforms logos that we also use on the /games, but a bigger version,
    probably 4x of the /games version. Use same service and approach. I care
    only about: PS5, Switch2, PC (and if possible instead of PC use Steam, GoG,
    Epic, one or more if apply).

19. Coming back to the left hand side, after a hairline we have the section
    "ownership" which will have:
    platforms [ ] PS5 [ ] Switch2 [ ] Steam [ ] GoG [ ] Epic (show only the ones that apply to the game and if you can't do PC details use PC with Steam logo)
    played [ ] PS5 ... can be the platforms from above that I have ownership. I cant play on some platform that the game isn't released for, or a platform I don't have the game.
    recorded [ ] PS5 ... can be the platforms from above, the ones that I played on. Can't be others.
    footage - we leave this black for now with a status badge in bright orange [TBD] - we'll search in the future once we reach the footage rewamping.

20. we add [resync] link in the breadcrumb instead of the current [edit] link;
    we need the sync lock mechanism and the link has to be mutted while the
    sync in in place like we have with the Voyage sync lock and we update the
    page with the same mechanism ActionCable websocket as /settings and Voyage.

21. On the left hand side, after the heatscore bar (or what the last thing was
    there), we add a hairline and we put the sync copy: syncced ~22m ago. We
    use our format, the short one. When resynccing (because of clicking the top
    breadcrumb link) we replace ~22m ago with our =--- indicator which will be
    updated once the sync is done.

22. The sync is overriding the current info for the fields that are coming from
    igdb, without touching the ownership fields. If the game is in a bundle /
    collection the coverart for that bundle has to be regenerated.

23. The sync job has to be implemented now and specced.

24. linked videos -> videos - shorter copy and replace the current copy "no
    linked videos yet" with status badge orange bright, that should be a
    component by now [TBD] so we can revisit later.

25. We add a new thing in the keybindings that is separated by the current
    navigation by a hairline and I think this new section should be the first
    one but I'm opened to suggestions to switch placement with the navigation.
    This new section is about actions on this page. In this section we move /
    search to it and it will be like now (we'll revisit later) and we continue
    with s sync that will trigger the sync on this page for this game and -
    delete that will pop up the modal

That's the /games revamp.
