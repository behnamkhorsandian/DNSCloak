# Designing for the Command Line Interface
[Library Textual](https://github.com/Textualize/textual.git)

## Main Colors

```
blue: #6090e3
red: #a25138
yellow: #e5e885
orange: #d59719
purple: #a492ff
green (my main color): #2eb787
light green: #9acfa0
dark green: #466242
light gray: #9ab0a6
dark gray (for sidebar): #343434
black (for background): #232323
white (for texts): #e7e7e7
```

## No Emojis
Only use ASCII Characters:
```
ASCII code 176 = ░ ( Graphic character, low density dotted )
ASCII code 177 = ▒ ( Graphic character, medium density dotted )
ASCII code 178 = ▓ ( Graphic character, high density dotted )
ASCII code 179 = │ ( Box drawing character single vertical line )
ASCII code 180 = ┤ ( Box drawing character single vertical and left line )
ASCII code 185 = ╣ ( Box drawing character double line vertical and left )
ASCII code 186 = ║ ( Box drawing character double vertical line )
ASCII code 187 = ╗ ( Box drawing character double line upper right corner )
ASCII code 188 = ╝ ( Box drawing character double line lower right corner )
ASCII code 191 = ┐ ( Box drawing character single line upper right corner )
ASCII code 192 = └ ( Box drawing character single line lower left corner )
ASCII code 193 = ┴ ( Box drawing character single line horizontal and up )
ASCII code 194 = ┬ ( Box drawing character single line horizontal down )
ASCII code 195 = ├ ( Box drawing character single line vertical and right )
ASCII code 196 = ─ ( Box drawing character single horizontal line )
ASCII code 197 = ┼ ( Box drawing character single line horizontal vertical )
ASCII code 200 = ╚ ( Box drawing character double line lower left corner )
ASCII code 201 = ╔ ( Box drawing character double line upper left corner )
ASCII code 202 = ╩ ( Box drawing character double line horizontal and up )
ASCII code 203 = ╦ ( Box drawing character double line horizontal down )
ASCII code 204 = ╠ ( Box drawing character double line vertical and right )
ASCII code 205 = ═ ( Box drawing character double horizontal line )
ASCII code 206 = ╬ ( Box drawing character double line horizontal vertical )
ASCII code 217 = ┘ ( Box drawing character single line lower right corner )
ASCII code 218 = ┌ ( Box drawing character single line upper left corner )
ASCII code 219 = █ ( Block, graphic character )
ASCII code 220 = ▄ ( Bottom half block )
ASCII code 221 = ¦ ( Vertical broken bar )
ASCII code 222 = Ì ( Capital letter I with grave accent )
ASCII code 223 = ▀ ( Top half block )
ASCII code 254 = ■ ( black square )
```



# Designing the Specify CLI | Specify
In a world where we’re surrounded by screens everywhere (in the street, in our house, on our bodies), we tend to forget what a significant portion of today’s makers are experiencing when giving life to digital products. A dark blank canvas, with less than 1,000 pixels in width and 800 pixels in height with no other animations than a blinking box. Welcome to the terminal, the mid-1960s interface people uses on the first computers and that we still use nowadays.

Tools like Warp, iTerm, Hyper.js, and ZSH, are sometimes the first ones to be installed on developers’ machines when setting up, as the terminal is one of their primary tools. Developers may also add customization and powerful features to make their terminal a little friendlier.

The core of the terminal lies in the Command-Line Interfaces (CLIs) experience provided by products like NPM, Yarn, GitHub, JEST, Stripe, and Squoosh — just to name a few. They succeeded in bringing interactivity on a screen not really optimized for that.

At Specify, we provide a CLI to developers to let them interact with our Design Data Platform. The [Specify CLI](https://specifyapp.com/blog/introducing-specify-cli) helps you sync design tokens and assets from Sources, like a Figma file, and to pull them to get a fully configurable output directly in their codebase — whatever your technologies are.

The Specify CLI is the developer tool companion for configuration file creation and iteration. It provides you feedback to validate your configuration and help you understand the logic behind rules and parsers.

An unusual but fun playground
-----------------------------

As a designer, designing for the first time a CLI isn’t really something you feel immediately comfortable with.

Let’s dive into each category — colors, typography, spacing, animations, components — and see how we can get the most out of the CLI possibilities.

### Colors

You have to deal with a strict amount of colors:

*   16 ANSI colors (with a normal and bright version for each): black, red, green, yellow, blue, magenta, cyan ;
    
*   3 “basic” colors: foreground, background and link colors — note that there is no user’s preferences detection regarding light or dark theme affecting the background and foreground colors here.
    

Each of these 19 colors has a dimmed variation (around 50% opacity), leading to a total of 38 colors. You can also use ANSI escape codes, but you can’t be sure if the user’s terminal is correctly handling it. And on top of that, users can override your design decisions anytime with the terminal's preferences! We’re very far from what we’re used to with modern web & app development.

![](https://framerusercontent.com/images/VxqQ9WMh6eMWdyD0FTPi3Is6i0w.webp)

##### Colors available when designing for CLI

We wanted to step away from very saturated colors for the Specify CLI. Instead, we added pastel vibes to prevent our users from losing sight while executing the `pull` command. We ensured every label background and foreground color had a good contrast ratio with Stark (above 4.5:1).

![](https://framerusercontent.com/images/box682BMfi4e86wzL2eSIHq4WlQ.webp)

##### Label color accessibility

In our first trials, we dealt with a very “Matrix-vibe”: a lot of green (or red if errors), not very easy to read. We stepped back from this option and decided to choose something more subtle for descriptions and paths, with `foreground-dimmed` (basically a gray if the foreground color is set to white).

![](https://framerusercontent.com/images/fDQUNwnfyWf0wfnYxfU5rShxsqk.webp)

##### Matrix vibes

![](https://framerusercontent.com/images/5yZnWvFF3ZnkI2vsEaW4VM5IRU.webp)

##### Pastel vibes

We were using bold text in our labels, and terminals have by default the “Brighten bold text” — which uses a gray instead of a black color, ugly and not accessible. As a workaround, we used “inverted colors” — inspired by JEST: you set the color on the label, and the text plays the role of a mask. As a result, your text takes the color of the background, and voilà.

### Typography & Spacing

Let’s talk a bit about typography. No exception here: Users can override every design decision: both font choices and font parameters (font-size, leading, kerning, etc). As a rule of thumb, we used a monospace font to have the most representative idea of the final interface.

At Specify, we designed it with the [Meslo](https://github.com/andreberg/Meslo-Font) typeface (one of the most popular fonts for terminals). We also really like the [Fira Code](https://github.com/tonsky/FiraCode) characters, the one we use in our platform and our documentation.

What about spacings, flows, and grids? Sorry friends, no exception here, again. You have to deal with an airport flight table, where spacing can only exist with a space character. All your spacings choices depend on the font the user uses. As a result:

*   Your horizontal spacings should use the width of a character (same for each character with a monospace font). For example, with a font like Meslo and font size set to 14px, it’s 9px. So, all your spacings should be a multiplier of 9: 18, 27, 36, etc.
    
*   Your vertical spacings should use the same height as your character, so the line-height. Line-height is often set to 1em by default, so 14px in our example. You can also set it to 18 or maybe 20px. All your spacings should be a multiplier of this number. In our example: 14, 28, 42, etc. Again, the user has the final word here. Keep in mind: Don’t hesitate to use an additional line of spacings between two elements for the best possible reading experience.
    

![](https://framerusercontent.com/images/nf0pu343T2vkwQk1TpB1nXdrt0.webp)

##### Vertical spacing: multiple of 18

![](https://framerusercontent.com/images/7hfCrE0WX105CjsuRZo9pMjXQMU.webp)

##### Horizontal spacing: multiple of 9

### Animations

Let’s put it simply. No animations, no transitions, only characters. The world of UTF-8 is [really fun to explore](https://twitter.com/yannglt/status/1506309554795073544?s=20), and you might find some creative combinations to represent lists, progress bars, and semantics.

To design the Specify CLI, we chose the classic-but-efficient `snake-dots` for loaders and some kind of photons-like characters to mimic our design data platform pipeline animation in our video for progress bars. For our icons, we found their four characters for semantic-state: `info`, `success`, `warning`, and `error`.

![](https://framerusercontent.com/images/QrlBfGZIk80K5qbMYlBwfz6oLNc.webp)

##### Animated components

We transformed each of these characters into a Figma Component and Variant. We used [Interactive Components](https://help.figma.com/hc/en-us/articles/360061175334-Create-interactive-components-with-variants) to make the transition between loading bar states with an after delay of 80ms to mimic the terminal speed while pulling design tokens and assets, itself contained in a header or a label component.

### Components

Speaking of components, we were lucky. [Ink](https://github.com/vadimdemedes/ink) helped us a lot in building bridges between design and code. Each label, header, callout, and rule has its own component in Figma and VS Code. We couldn’t really use design tokens here, unfortunately (and yes, we’d have loved to do some dogfooding with Specify here) as we used system colors and user preferences.

![](https://framerusercontent.com/images/ww1Q3G5O5lTRQ45rmWWoddQ7M.webp)

# Designing for the Command Line Interface (TUI)
In a world where we’re surrounded by screens everywhere, we tend to forget what a significant portion of today’s makers are experiencing when giving life to digital products. A dark blank canvas, with less than 1,000 pixels in width and 800 pixels in height with no other animations than a blinking box. Welcome to the terminal, the mid-1960s interface people use on the first computers and that we still use nowadays.

Tools like Warp, iTerm, Hyper.js, and ZSH, are sometimes the first ones to be installed on developers’ machines when setting up, as the terminal is one of their primary tools. Developers may also add customization and powerful features to make their terminal a little friendlier.

At [Specify](https://specifyapp.com/), we provide a CLI to developers to let them interact with our Design Data Platform. The Specify CLI helps you sync design tokens and assets from Sources, like a Figma file, and to pull them to get a fully configurable output directly in their codebase — whatever your technologies are.

Context
-------

The Specify CLI is the developer tool companion for configuration file creation and iteration. It provides you feedback to validate your configuration and help you understand the logic behind rules and parsers.

Under the hood, Specify requires users to provide configuration files to transform their design data (colors, text styles, icons, etc.): changing the case, adding suffixes or prefixes, converting values, creating files in the right place with the correct name. 

To be validated, these configuration files need to respect a specific structure. We improved our Command Line Interface (CLI) to provide meaningful feedback with hints, warnings, and error messages.

Research
--------

I researched CLI patterns, best-in-class examples, [Amanda Pinsker's Config talk](https://www.youtube.com/watch?v=zsjeZZVAk1E) about GitHub CLI, read [Command Line Interface Guidelines](https://clig.dev/).

I also paid closer attention to the CLI tools I was already using and created a moodboard with examples of NPM, Yarn, GitHub, JEST, Stripe, Squoosh, and Typescript Tests.

### Stack

We listed what we needed with engineers and choose to use Ink and Chalk for this project to achieve these desired UI results:

*   indent information on multiple levels with progress bars for each
    
*   apply color and background color / highlight to text
    
*   display progress bars
    

Building
--------

Command line interface being probably the interface users can customize the most, I had to try multiple configurations: light/dark mode, color schemes, density, and fonts.

### Colors

After digging into the American National Standards Institute (ANSI) colors, I realized I would have to deal with a rigorous amount of shades, 38 precisely:

*   16 ANSI colors (black, red, green, yellow, blue, magenta, cyan) with a normal and bright version for each one
    
*   and 3 “basic” ones for the foreground, background, and links — note that there is no user preference detection regarding light or dark themes affecting the background and foreground colors here.
    

Each of these 19 colors has a dimmed variation (around 50% opacity) — leading to a total of 38 colors.

![CLI Colors](https://framerusercontent.com/images/h47jhTBRuIWhrkeiW72HtOyCeNg.jpg)

### Iconography

Then, I started exploring UTF-8 possibilities and characters available for progress bars, indents, and feedback icons, like a checkmark for successes, an exclamation point for warnings, or a cross for errors, as icons can't be displayed on terminals. Finally, I ended up with enough symbols to cover all use cases.

![UTF-8 Characters](https://framerusercontent.com/images/YN5386deVMWjxHnHsv1PCQ57vuY.jpg)

### Typography

Similar to colors, users can override both font choices and font parameters (font size, leading, kerning, etc.). As a rule of thumb, I used a monospace font[¹](about:blank/2024-retrospective#footnotes) to have the most representative idea of the final interface. 

The only thing you can control is proportion. So I paid a lot of attention to the spacing system applied and when to use bold vs. keeping a regular font weight — while keeping in mind that the final display behaves like an airport flight table with rows and columns and a fixed-size box.

![CLI Flight table](https://framerusercontent.com/images/hicI9BxpEXmst7UdOd3gedGwbU.jpg)

### Spacing

Horizontal spacings should use the width of a character (same for each character with a monospace font) while vertical spacings should use the same height as a character’s line height (or leading).

![CLI Horizontal Spacing](https://framerusercontent.com/images/XYRy3DgiB4vLdkYTAcYzOSNYSg.jpg)![CLI Vertical Spacing](https://framerusercontent.com/images/bF0GrxCLdXdg9kM2JZCBPocY.jpg)

### Components

I created components and variants in Figma using Variants[²](about:blank/designing-for-command-line-interface#footnotes), and engineers replicated them in React. To mimic the reality as far as possible in Figma, I created a set of Interactive Components[³](about:blank/designing-for-command-line-interface#footnotes) for the header, progress bar, and processed rule.

![CLI Components](https://framerusercontent.com/images/MwmvZNiqMIGBwIHm8oYZrZ6E4c8.jpg)

As a result, we got 12 high-fidelity prototypes and iterated with engineers on successful extractions, error states, sync, help, new version, trial end, and missing payment.

![CLI Examples](https://framerusercontent.com/images/TyFMQ9VKuSkvPrXPuREm9MEAnQ.jpg)