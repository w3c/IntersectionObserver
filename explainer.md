# Position Observers Explained

## What's All This About?

This repo outlines an API that can be used to understand the visibility and position of DOM elements relative to a viewport. The position is delivered asynchronously and is useful for understanding the visibility of elements, managing pre-loading of DOM and data, as well as deferred loading of "below the fold" page content.

## Observing Position

The web's traditional position calculation mechanisms rely on explicit queries of DOM state that are known to cause style recalcuation and layout and, frequently, are redundant thanks to the requirement that scripts poll for this information.

A body of common practice has evolved that relies on these behaviors, however, including (but not limited to):

  * Observing the location of "below the fold" sections of content in order to lazy-load content.
  * Implementing data-bound high-performance scrolling lists which load and render subsets of data sets. These lists are a central mobile interaction idiom.
  * Calculating element visibility. In particular, [ad networks now require reporting of ad "visibility" for monetizing impressions](http://www.iab.net/iablog/2014/03/viewability-has-arrived-what-you-need-to-know-to-see-through-this-sea-change.html). This has led to many sites abusing scroll handlers, [synchronous layout invoking readbacks](http://gent.ilcore.com/2011/03/how-not-to-trigger-layout-in-webkit.html), and resorting to exotic plugin-based solutions for computing "true" element visibility (as a fraction of the element's intended size).

These use-cases have several common properties:

  1. They can be represented as passive "queries" about the state of individual elements with respect to some other element (or the global viewport)
  1. They do not impose hard latency requirements; that is to say, the information can be delayed somewhat asynchronously (e.g. from another thread) without penalty
  1. They are poorly supported by nearly all combinations of existing web platform features, requiring extraordinary developer effort despite their widespread use.

A notable non-goal is pixel-accurate information about what was actually displayed (which can be quite difficult to obtain efficiently in certain browser architectures in the face of filters, webgl, and other features). In all of these scenarios the information is useful even when delivered at a slight delay and without perfect compositing-result data.

Given the opportunity to reduce CPU use, increase battery life, and eliminate jank it seems like a new API to simplify answering these queries is a prudent addition to the web platform.

### Proposed API

We propose an API which allows a developer to frame questions about _"is an element inside a particular viewport?"_

```js
var observer = new PositionObserver({
    viewport:         /* element || null */,
    /* Same as margin, can be 1, 2, 3 or 4 components, possibly negative lengths.
     * "5px"
     * "5px 10px"
     * "-10px 5px 5px"
     * "-10px -10px 5px 5px"
     */
    viewportModifierLength: /* string */,
    viewportModifierTime: /* Time expanding the viewport rect, e.g. will intersect the viewport in 3 seconds given the current scroll curve. */,
    /* Whether to give callbacks only when an element starts/stops intersecting
     * a viewport or everytime it changes how much it intersects the viewport.
     * Callback only fire if the element isn’t intersecting an edge of the
     * viewport in the case that the element jumps from being entirely outside
     * the viewport to entirely inside it.
     * Defaults to true, a less power-hungry option. */
     thresholdCallbacks: true
  },
  function(changes) {
    changes.forEach(function(c) {
      console.log(c.time);               // Timestamp set by the compositor
      console.log(c.boundingClientRect); // May include a bit to discuss
                                         // fully or partially visible
      console.log(c.viewport);           // a Rect
      console.log(c.element);
      console.log(c.velocity);
      console.log(c.timeToViewport);
    });
  },
);

// Watch all threshold events on a specific descendant of the viewport
observer.observe(childElement);
observer.unobserve(childElement);

observer.disconnect(); // removes all
```

This API uses the outermost document's inherent viewport -- i.e. "the thing the user sees" -- as the default viewport. Other queries can be formed relative to ancestor elements.

The "natural" viewport isn't represented anywhere in the DOM and so queries against it are a bit magical, but this is reasonable as the information is available through other (expensive) mechanisms today. Should the viewport hierarchy become exposed to DOM, this API can be explained in those terms.

Thanks to the "natural" viewport, code can be hosted inside an iframe which can report the visibility of the queried element as the user scrolls the iframe (and element) into view.

## Element Visibility

The information provided by this API, combined with the default viewport query, allows a developer to easily understand when an element comes into (and out of) view. Here's how one might implement the IAB's "50% visible for more than a continuous second" policy for counting an ad impression:

```html
<!-- the host document includes (or generates) an iframe to contain the ad -->
<iframe id="theAd"></iframe>
<!-- it also includes ad script -->
<script src="//cdn.example.com/ads.js" async></script>
```

```js
// ads.js

// These functions left as an exercise to the reader
function logImpressionToServer() { /* ... */ }
function boundingBoxPct(boundingClientRect) { /* ... */ }

function getComputedOpacity(element) {
  return document.defaultView.getComputedStyle(element).opacity;
}

function wasVisible(element, changeRecord) {
  if (intersectPercentage(changeRecord.viewport,
           boundingBoxPct(changeRecord.boundingClientRect)) < 50) {
    return false;
  }

  return (getComputedOpacity(element) === 1);
};

function processChanges(changes) {
  changes.forEach(function(changeRecord) {
    var element = changeRecord.element;
    var wasVisibleInFrame = wasVisible(element);
    if (element.visibleStartTime) {
      if (wasVisibleInFrame) {
        if (changeRecord.time - element.visibleStartTime > 1000) {
          logAdImpressionToServer();
          observer.unobserve(element);
          return;
        }
      } else {
        element.visibleStartTime = null;
      }
    } else if (wasVisibleInFrame) {
      element.visibleStartTime = changeRecord.time;
    }
  });
}

var observer = new PositionObserver(
  { thresholdCallbacks: false },
  processChanges
);

var theAd = document.querySelector('#theAd');
observer.observe(theAd);
```

In this usage the `thresholdCallbacks` flag is set to `false` to ensure that every movement of the element is recorded while it intersects the viewport (in this case, the visible area of the tab). This higher rate of delivery might seem expensive at first glance, but note the power and performance advantages over current practice:

  - No scroll handlers need be installed/run (a frequent source of jank)
  - No timers are registered. Off-screen ads do not deliver any events until they come into view
  - No timeouts, polling, synchronous layouts, or plugins are required

## Data Scrollers

Many systems use data-bound lists which manage their in-view contents, recycling DOM to remain memory and layout-efficient while triggering loading of data that will be needed at some point in the near future.

These systems frequently want to use different queries on the same scroll-containing viewport. Data loading can take a long time, so it is advantageous to pre-populate data stores with significantly more information than is visible. The rendered element count may display a much smaller subset of available data; only the "skirt" on each side of a scrolling area necessary to keep up with scrolling velocity (to avoid "blank" or "checkerboard" data).

We can use a `PositionObserver` on child elements of a parent scrolling element to inform the system when to load data and recycle scrolled-out-of-view elements and stamp new content into them for rendering at the "end" of the list:

```html
<style>
  .container {
    overflow: auto;
    width: 10em;
    height: 30em;
    position: relative;
  }

  .inner-scroll-surface {
    position: absolute;
    left: 0px;
    top: 0px;
    width: 100%;
    /* proportional to the # of expected items in the list */
    height: 1000px;
  }

  .scroll-item {
    position: absolute;
    height: 2em;
    left: 0px;
    right: 0px;
  }
</style>

<div id="container">
  <div id="inner-scroll-surface">
    <div class="scroll-item" style="top: 0em;">item 1</div>
    <div class="scroll-item" style="top: 2em;">item 2</div>
    <div class="scroll-item" style="top: 4em;">item 3</div>
    <!-- ... -->
  </div>
</div>
```

As the user moves the `container`, the children can be observed and as they cross the threshold of the scrollable area, a manager can recycle them and fill them with new data instead of needing to re-create the items from scratch.

```js
function query(selector) {
  return Array.prototype.slice.apply(document.querySelectorAll(selector));
}

function init() {
  var observer = new PositionObserver({
      viewport: document.querySelector(".container"),
      viewportModifierTime: "1s"
    },
    manageItemPositionChanges
  );
  // Set up observer on the items
  query(".inner-scroll-surface > .scroll-item").forEach(function(scrollItem) {
    observer.observe(scrollItem);
  });
}

function manageItemPositionChanges(changes) {
  // ...
},
```

Many scrollers also want to fetch even more data than what's displayed in the list. We can create a second observer with a much larger "skirt" outside the viewport which will allow us to fetch a larger data set to account for latency.

## Delay Loading

Many sites like to avoid loading certain resources until they're near the viewport. This is easy to do with Position Observers:

```html
<!-- index.html -->
<div class="lazy-loaded">
  <template>
    ...
  </template>
</div>
```

```js
function query(selector) {
  return Array.prototype.slice.apply(document.querySelectorAll(selector));
}

var observer = new PositionObserver({
    // Pre-load items that are 1 second of scrolling outside the viewport
    viewportModifierTime: "1s"
  },
  function(changes) {
    changes.forEach(function(change) {
      var content = container.querySelector("template").content;
      container.appendChild(content);
      observer.unobserve(change.element);
    });
  }
);

// Set up lazy loading
query(".lazy-loaded").forEach(function(item) {
  observer.observe(item);
});
```

## Open Design Questions

This is a sketch! We've tried to pattern the initial design [`Object.observe()`](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Object/observe) and [DOM's Mutation Observers](https://developer.mozilla.org/en-US/docs/Web/API/MutationObserver). It's unclear if we should simply make this a special form of Mutation Observer.

There's a question about occlusion: should we try to lean on computed opacity or should the API only ever report quads that have no occlusion/filtering/transforms of any kind?

The specific timing of of change record delivery is also TBD.

Is the magical top-level viewport too magical? What are the alternatives?

Is it meaningful to have overdraw queries against the default viewport?

