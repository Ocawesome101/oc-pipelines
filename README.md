# Pipelines

Pipelines is a system where virtually all behavior is customizable.  All interactions are defined by pipelines, stored as `.pipeline` files in `/plumber/pipelines`.

Each pipeline has one or more wells (sources), zero or more pipes, and one or more faucets (sinks).  A pipeline can be thought of as analogous to unix's standard shell pipelines, but perhaps more powerful thanks to its extra capabilities.

The general format for each line of a `.pipeline` file is as follows: `type: name(arguments) input(extraInputName) output(extraOutputName)`.

  - `type` must be one of `well`, `pipe`, or `faucet`.  As a special case, if `type` is `#` (comment), the entire line is ignored.
  - `name` specifies the name of the pipeline component.  e.g. `foo` tells the system to use `/plumber/plumbing/foo.lua` as that component.
  - `(arguments)` is an optional comma-separated list of arguments.  This can contain arbitrary varargs to the whole pipeline, like:
    * `v[n]` to use the `n`th vararg
    * `...` to use every vararg
    Both of these may be used multiple times throughout the file.
  - The `input` and `output` directives may be used to construct additional named connections between arbitrary pipeline components.  They are completely optional and may be repeated as many times as necessary.  Note that pipelines constructed using this method share a buffer, and as such are only suitable for many-into-one connections and not one-into-many.

As an example, let us examine a pipeline definition file for the shell:

```
well: readkey output(screen)
pipe: shell(interactive)
faucet: screen input(screen)
```

The first line instructs the system to use the `readkey` pipeline stage as a well for this pipeline, and construct an extra `screen` output.

The second line specifies an interactive shell as the pipe.

The third line creates a `screen` faucet for the pipeline, and connects the `screen` output from the first line's `readkey` to an extra input of this pipeline.

We may also look at the `cat` pipeline:

```
well: file(...)
faucet: screen(nocursor)
```

This is simpler, merely constructing a two-stage pipeline that passes data from a given `file` to a new screen object.  This object is created with no cursor.


## Included pipeline stages

#### `dir`
Takes one argument, a path, and outputs a listing of all files from that path.

#### `dummy`
Echoes its first input connection to any output connections.

#### `file`
Like `dir`, but outputs the contents of a file.

#### `lines`
Appends a newline to all input messages it receives, and outputs the result.

#### `readkey`
Reads text input from the user.  Requires an extra `screen` connection like done in the `shell` pipeline shown above.

#### `screen`
Manages text output on a screen.  Multiple concurrent instances should behave correctly provided only one of them manages cursor blink (i.e. all but one are given the `nocursor` argument).

#### `shell`
A minimal shell.  Processes each input message as a shell command.  See the output of the `help` command for details.


## Plumber API

The Pipelines core, Plumber, provides a fairly minimal API.  All functions defined below are provided in the global `plumber` table.

#### `getGraphicsOutput(): table|string|nil`
Returns the GPU used for text output on boot.  May be a string or `nil` if a GPU and screen combo was unavailable at boot time.

#### `setGraphicsOutput(string|table)`
Set the GPU used for text output.  Provided argument must be either a full component address or a proxy.

#### `setLogOutput(function)`
Sets a function to be called when the system needs to log an event.  Its argument should be a single string.

#### `loadPipeline(string[, string]): table`
Loads a given pipeline from `/plumber/pipelines`.  Takes a pipeline name and optionally a comma-separated list of varargs.

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