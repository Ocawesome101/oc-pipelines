# Pipelines

Pipelines is a system where virtually all behavior is customizable.  All interactions are defined by pipelines, stored as `.pipeline` files in `/plumber/pipelines`.

Each pipeline has one or more *pipes*.  A pipeline can be thought of as analogous to unix's standard shell pipelines, but perhaps more powerful thanks to its extra capabilities.

The general format for each line of a `.pipeline` file is as follows: `type: name(arguments) input(extraInputName) output(extraOutputName)`.

  - `type` may be any value and it is recommended to be left blank.  As a special case, if `type` is `#` (comment), the entire line is ignored.
  - `name` specifies the name of the pipeline component.  e.g. `foo` tells the system to use `/plumbing/foo.lua` or `/plumber/plumbing/foo.lua` as that component.
  - `(arguments)` is an optional comma-separated list of arguments.  This can contain arbitrary varargs to the whole pipeline, like:
    * `v[n]` to use the `n`th vararg
    * `...` to use every vararg
    Both of these may be used multiple times throughout the file.
  - The `input` and `output` directives are used to construct named connections between arbitrary pipeline components.  They may be repeated as many times as necessary.  Note that pipelines constructed using this method share a buffer, and as such are only suitable for many-into-one connections and not one-into-many.

As an example, here is the pipeline definition file for the shell:

```
#: constructs a `readline` source with two outputs
: readline output(screen) output(shell)
#: constructs a `shell` pipe with one input and one output
: shell(interactive) input(shell) output(screen)
#: constructs a `screen` faucet with one input
: screen input(screen)
```

We may also look at the `cat` pipeline:

```
#: regurgitate data from a file specified through varargs
: file(...) output(screen)
#: output that data, and do not control the cursor blink state while doing so
: screen(nocursor) input(screen)
```

## Included pipeline stages

#### `dir`
Takes one argument, a path, and outputs a listing of all files from that path.

#### `dummy`
Echoes any arguments to any output connections, then echoes data from its first input connection, if present, to any output connections.

#### `edit`
A very basic and very minimal text editor.  Think `ed`.  Commands are taken through a `control` input and file data is taken through a `data` input.  Outputs some information to a `screen` output and some other information to every output.

#### `file`
Like `dir`, but outputs the contents of a file.

#### `ghapi`
Some basic interfaces with the GitHub API:
  - `ghapi(request)` gives the URL of a request.  Pass this to `inetget`.
  - `ghapi(request,parse)` parses the result of an API request.  Currently supports `urls` togive a list of URLS from a `repos/git/trees` request.

See the included `update` pipeline for some sample usage.

#### `inetget`
Has two modes of operation:
1) Reads a list of URLs from its inputs and processes them in order.  Each data block is preceded by a `{"url", number, string, table}` and succeeded by a `{"done"}`.
2) Reads data from one single URL, provided as an argument; the output of this mode has no additional metadata and is only the resulting text content.

#### `lines`
Splits each input message it receives into individual lines, and outputs the result.  If given `buffer`, will merge multiple messages together where necessary.

#### `match`
Applies `string.match` to each input message it receives.  Arguments are an optional `datatype` filter and a pattern.  The `datatype` filter is used to filter by data type - `string` or `table[index]`.

#### `readline`
Reads text input from the user.  Requires a `screen` connection as shown in the `shell` pipeline above.

#### `screen`
Manages text output on a screen.  Multiple concurrent instances should behave correctly provided only one of them manages cursor blink (i.e. all but one are given the `nocursor` argument).

#### `shell`
A minimal shell.  Processes each input message as a shell command.  See the output of the `help` command for details.

#### `updatechecker`
Takes a base directory as an argument, reads `update.cfg`, and the output of a `repos.branches` request from `ghapi`, and if a newer commit is available than the one specified in the `update.cfg` it will output the repository name and branch for use with `ghapi`.

See the included `update.pipeline` for intended use.

#### `writer`
Takes a base directory as an argument, and reads file data.  Interprets any tables present in the datastream as having their first field be a file path.  e.g. if it receives `{"/foo.txt"}` it will switch to `base/foo.txt`.

## Plumber API

The Pipelines core, Plumber, provides a fairly minimal API.  All functions defined below are provided in the global `plumber` table.

#### `getGraphicsOutput(): table|string|nil`
Returns the GPU used for text output on boot.  May be a string or `nil` if a GPU and screen combo was unavailable at boot time.

#### `setGraphicsOutput(string|table)`
Set the GPU used for text output.  Provided argument must be either a full component address or a proxy.

#### `log(message)`
Logs a message to the current log output.

#### `setLogOutput(function)`
Sets a function to be called when the system needs to log an event.  Its argument should be a single string.

#### `loadLibrary(string): any`
Loads a library from `/libraries` or `/plumber/libraries`.

#### `loadPipeline(string[, string]): table`
Loads a given pipeline from `/pipelines` or `/plumber/pipelines`.  Takes a pipeline name and optionally a comma-separated list of varargs.

#### `startPipeline(string[, string]): number`
Loads the given pipeline, adds it to the scheduler queue, and returns its ID.

#### `tickPipeline(table): number`
Runs one stage of the given pipeline object and returns a minimum timeout.  Should be left alone unless you know what you're doing.

#### `getRunningPipelines(): table`
Returns a table with one of `{id=number, name=string}` for every pipeline in the scheduler queue.

#### `waitForPipeline(number)`
Waits for a pipeline with the specified ID to complete i.e. leave the scheduler queue.

#### `completeCurrentPipeline()`
Marks the current pipeline as completed.  Execution of the pipeline will cease after the current scheduler cycle.

#### `getInputs(): table`
Returns a table with one of `{id=number, type=string, active=boolean}` for every input to the current pipeline stage.

#### `getOutputs(): table`
Like `getInputs`, but provides results for the current pipeline stage's outputs instead.

#### `pollInput(number): any`
Returns the first value present in the current stage's input stream with the given ID, if one is present.  Otherwise returns `nil`.

#### `pollInputs(): table`
Returns a table containing the IDs of all inputs that currently have values available for reading.

#### `waitInput(number, number): any`
Like `pollInput()`, but waits for a value to become available.  Optionally takes a timeout value, in seconds, as its second argument.

#### `waitInputs(number): table`
Like `pollInputs()`, but waits for a value to become available.  Optionally takes a timeout value, in seconds, as its only argument.

#### `pollSignal(): ...`
Returns the first signal in the pipeline's signal queue, if one is present, in the same manner as `computer.pullSignal()`.

#### `waitSignal(): ...`
Like `pollSignal()`, but waits for a signal to become available.

#### `writeSingle(number, ...)`
Writes all given values sequentially to the output with the given ID.

#### `write(...)`
Writes all given values sequentially to all outputs of the current pipeline stage.

#### `readGlobalState(string)`
Reads a global state value using the given key.

#### `writeGlobalState(string, any)`
Writes a global state value for the given key.

Plumber also provides a minimally abstracted `fs` API.  Its functions are almost exactly the same as the filesystem component, but it allows arbitrary mounts and abstracts file handles slightly to make them nicer to work with.
