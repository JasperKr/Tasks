# Tasks
Task system in lua using multithreading

This is a copy of the task system from my game engine, it is a simple task system that uses multithreading to run tasks in parallel.

You can also use the `wrapAsyncFunction` function to work more easily with async functions. Like tasks but also stuff like graphics readback, etc.

## Example
```lua
local Task = require("Tasks")

function love.update(dt)
    Task.runTasks()
end

Task.wrapAsyncFunction(function()
    local thread = Task.newTaskThread [[
        print(...)
    ]]

    for i = 1, 10 do
        Task.newSyncedTask(thread, { "Hello, world", i })
    end
end)

function love.quit()
    Task.Shutdown()
end
```
This works because `wrapAsyncFunction` will run the function as soon as you call it, but it isn't strictly needed in this case, since we don't have any blocking code.

## API
#### `Task.newTaskThread(script: string, isPath: boolean): `thread
Creates a new task thread with the given script, or file path.

#### `Task.newTask(thread: thread, args: table, callback: function): task`
Creates a new task with the given script, or file path. This task will be added to the current task group.

#### `Task.newSyncedTask(thread: thread, args: table, callback: function): task`
The same as `newTask` but will create a new group of tasks. So it waits for the previous task/group to finish before starting.

#### `Task.newAsyncTask(thread: thread, args: table, callback: function): task`
The same as `newTask` but will reset the task group. So it will run in parallel with the previous task/group.

#### `Task.taskStatus(task: task): string`
Returns the status of the task.
#### Possible values:
- `"running"`: The task is running.
- `"done"`: The task is done.
- `"queued"`: The task is queued.

#### `Task.groupStatus(group: taskGroup): string`
Returns the status of the task group.
#### Possible values:
- `"running"`: The task group is running.
- `"done"`: The task group is done.
- `"queued"`: Not all tasks in the group are done running.

#### `Task.newTaskGroup(dependencies: table<taskGroup> | taskGroup | nil): taskGroup`
Creates a new task group with the given dependencies.
A task group is a group of tasks that will run in parallel, but will never run before any of the dependencies are done.
This can be useful if you have a bunch of tasks that can run in parallel, but you need to wait for some of them to finish before starting others.

#### `Task.runTasks(): nil`
Runs all tasks that are queued.

#### `Task.setTaskGroup(group: taskGroup): nil`
Sets the current task group.

#### `Task.setNewTaskGroup(dependencies: table<taskGroup> | taskGroup | nil): nil`
Sets the current task group to a new task group with the given dependencies.

#### `Task.wrapAsyncFunction(func: function, doneCallback: function, busyCallback: function, ...: any): nil`
Wraps a function to run as a coroutine. This is useful for when you need to await other tasks or other async functions. So you don't block the main thread.

#### `Task.demand(...: task | taskGroup): nil`
Wait for all the given tasks or groups to finish before continuing.

#### `Task.Shutdown(): nil`
Shuts down the task system, this will stop all tasks and threads. (This is needed for cleanup of your program)

## Functions for inside wrapped async functions
You cannot use these outside of a wrapped async function.

#### `Task.await(data: task | taskGroup, ...: any): any`
Wait for a task to finish and if it hasn't finished yet, yield the coroutine with the given arguments. This will return the results of the `coroutine.yield` call.

#### `Task.barrier(func: function, ...: any): nil`
Run a function with the given arguments, until it returns true. This is useful for waiting for a condition to be true, like starting a bunch of tasks and waiting for them to finish.

#### `Task.yield(condition: boolean): any`
Yield the coroutine if the condition is true. 
This is useful if you want to run parts of the function over multiple frames to not block the main thread.

## task group methods:
- `taskGroup:isRunning()`: boolean - Returns if the task group is running.
- `taskGroup:isDone()`: boolean - Returns if the task group is done.
- `taskGroup:isQueued()`: boolean - Returns if any task in the group is queued.
- `taskGroup:canRun()`: boolean - Returns if the task group can run. (Mostly used internally)

## Extra functions
These functions are for getting information about the tasks, they are not needed for the task system to work.

#### `Task.getThreadCount(): number`
Returns the amount of threads that the task system is using.

#### `Task.getInfo(): table<{ active: boolean }>`
Returns information about the threads.

#### `Task.getActiveThreadCount(): number`
Returns the amount of active threads.

#### `Task.getWrappedFunctionsCount(): number`
Returns the amount of wrapped functions that are running.

#### `Task.getQueuedTaskCount(): number`
Returns the amount of tasks that are queued.