# Changelog

## 2.5.0
- Cart missing works away from home. The button and the missing counts used
  to show up only while you stood in your house, because the counts were
  taken against that house. The picker now asks for them against your storage
  alone, so you get the same numbers at a vendor, at the auction house or in
  a neighbor's living room.
- A blueprint's page in the picker has a new "Count placed decor" tick. It
  starts off, and then only what sits in your storage counts as owned. Tick
  it and pieces already placed in your house count too, the way it used to
  work indoors, except now from anywhere. It reads the house you stand in, or
  one of your own when you're away, and with two houses a button next to the
  tick picks which. Room blueprints don't show the tick, since adding a room
  leaves your placed decor where it is and the game counts a room against
  storage either way.
- Blizzard's blueprint window shows the Cart missing button outside a house
  too. Opened indoors it keeps Blizzard's own counts, placed pieces included,
  so the button agrees with the marks in that window.
- The picker no longer prices every blueprint by itself each time it opens.
  Those lookups go through the same line to the server a click does, so with
  a handful of blueprints you sat waiting before one would open. A Price all
  blueprints button under the list starts the run now, counts down while it
  goes and stops it on a second click. Opening a blueprint still prices that
  one, and prices stay for the session.
- The Full set and Missing lines under a blueprint's pieces cut off once a
  few currencies pile up. Hovering either one now spells the whole bill out
  in a tooltip, tinted by what your purse covers, like the cart's own total.

## 2.4.0
- Carted pieces that only the auction house sells now show a price too, read
  from Auctionator or Oribos Exchange when you have one of them. It wears
  the same ~ the other estimates do, the footer sums it up as its own auction
  share next to the vendor part, and hovering a row's price tells you which
  addon the number came from.
- Blueprints now come priced. The picker's list shows what each one runs
  next to its name, filled in quietly as the picker sits open. Opening one
  sums the full set and the missing part under its pieces, and Blizzard's
  blueprint window carries the same totals above the cart buttons, with the
  full breakdown and your purse colors in their tooltips.
- The cart's blueprint section says where it came from: pieces all carted
  from one blueprint put its name in the section header.
- The cart's header grew a Patch notes button. It blinks after an update
  with something new until you read the notes, then stays quiet.

## 2.3.2
- A blueprint the size of a whole house left the shopping cart looking empty.
  The rows were there and the total counted them. Hovering one even brought
  its tooltip up, but nothing drew. The list now builds only the rows that
  fit on screen and reuses them as you scroll, so a couple of thousand pieces
  sit in it as happily as ten. The blueprint picker's contents page had the
  same trouble and got the same fix.
- Carting a big blueprint was slow on top of that, because every piece
  rebuilt the whole list on its way in. They all go on in one pass now. Past
  five thousand pieces the cart buttons ask before filling the list that far.

## 2.3.1
- Leaving your house left the shopping cart stuck out of sight. Neither /cart
  nor the add buttons brought it back, and nothing complained about it. The
  cart now comes up wherever you are.
- Blueprint pieces came up as a page of question marks when the picker was
  opened straight after a loading screen. The icons now arrive as the game
  hands the data over, and a dye carted before its icon loaded no longer
  keeps the question mark for good.

## 2.3.0
- Blueprints can fill the cart. Blizzard's blueprint window carries a "Cart
  all" and a "Cart missing" button, and the cart itself has a blueprint
  picker behind the "or add from a blueprint" link, so a whole build's worth
  of decor and dye lands on the list in one click. Adding the same blueprint
  again tops the rows up to what it needs instead of stacking on top, and
  asks first if you really do want another full set.
- The list is split into Decor, Dyes and From blueprints. Each section
  collapses on its own and carries its own Buy all and auction house search.
  Drag the cart wider and the rows flow into columns, up to five of them,
  and the Reset button in the corner brings the window back if it ends up
  somewhere unreachable.
- The planned total now says whether you can pay it. Each part of the sum
  is green while your purse covers it and red once it does not, and hovering
  the total puts what you hold next to what the cart asks for.
- Hovering a section's Buy all prices up what this vendor stocks from that
  section, colored the same way. Clicking it while you cannot afford the lot
  now says what you are short and how many items will go through before
  anything is bought.

## 2.2.1
- Ready for patch 12.1. The game renames the lookup that turns a dye item
  into its colors there, and dropping a dye on the cart now works with both
  the old and the new name, so nothing breaks on patch day.

## 2.2.0
- The cart carries its own paint catalog now. The "pick a dye" link slides
  it out beside the cart with every dye in the picker's categories, so dyes
  can be carted from anywhere, no house editor needed.
- Without Auctionator the AH button no longer stops at the browse list, it
  lands straight on the item's purchase page with the planned amount
  preset. The game grumbles an internal auction house error over a preset
  amount even though the buy goes through fine, so that one message is
  hidden while a preset is in play. Real errors still show.
- The windows remember where you dragged them between sessions, and the
  cart also keeps its size.
- A Ctrl-click add flies all ten icons into the cart instead of five.

## 2.1.0
- Cart items now get crossed off no matter where they come from. An auction
  win pulled from the mailbox, a crafted piece, a trade, anything that lands
  in your bags counts against the list, not just vendor buys.
- Dyes can go in the cart. Hover a swatch in the dye picker while
  customizing decor and hit the + (or Ctrl-click), click again to plan
  more, or drag a dye item in from your bags. A vendor selling a carted dye
  records its price like any decor piece. Dye rows draw compact, and decor
  rows got tighter too.
- At the auction house, carted items with no known vendor price show an AH
  button. With Auctionator installed it searches through the shopping tab
  with the planned counts attached, and a Search AH button runs the whole
  unpriced list at once. Without Auctionator the button searches too, with
  the results landing in the stock browse list. Buying a carted dye ticks
  the list the moment the purchase goes through, and collecting the
  delivery from the mail later will not tick it twice. The cart opens by
  itself at the AH when something unpriced is on the list, same as at a
  stocked vendor.
- While no decor is selected, the drop zone offers an "or add from the
  catalog" link. It opens the housing dashboard on the catalog tab, where
  the + buttons live.

## 2.0.1
- The addon list title is now "QoLify: Standalone Decor Tools", matching how
  the rest of the QoLify family is named. Nothing else changed.

## 2.0.0
- Renamed to Decor Tools. The spend watching stays as it was, and a decor
  shopping cart joins it.
- The cart is a wish list for decor, opened with /cart. Catalog entries get a
  small + button in the house editor storage and on the housing dashboard, a
  decor selected in edit mode can be dropped in by clicking the cart box, and
  decor items drag in from bags. Shift adds 5 at once, Ctrl 10.
- Carted items show their price. The catalog gives an estimate, marked with ~,
  and visiting a vendor that sells the item records the real cost, whether
  gold, a currency, barter items or a mix. Hovering a cost icon tells you what
  it is, and the footer sums up the whole plan.
- At a vendor, carted items carry a "buy N" tooltip line that counts down as
  you buy. Rows grow a Buy button for items the open vendor sells, and Buy all
  buys everything it can at three a second, with a confirm step first.
- Walking up to a vendor that stocks something from the cart opens the cart by
  itself, and leaving closes it again unless you had it open already.
- The cart stays up in house edit mode, closes on Escape and resizes from its
  bottom right corner.
- The minimap button opens the cart on left click and the spend watcher on
  right click.

## 1.1.0
- Cap warning now only shows on decor, not every item over the cap at a decor vendor.

## 1.0.0
- First release.
