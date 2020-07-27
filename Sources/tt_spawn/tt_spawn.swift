import Ctt_spawn
import Foundation

//this is a protocol that represents a simple one-way POSIX pipe with two file handles (one file handle for reading, one file handle for writing)
public protocol PosixSystemPipe {
	var writing:Int32 { get }
	var reading:Int32 { get }
}

//will convert a collection of strings into an array of pointers that can be used with various C functions
extension Collection where Element == String {
	fileprivate func as_c_array<R>(_ work:(Optional<UnsafeMutablePointer<UnsafePointer<Int8>?>>) throws -> R) rethrows -> R {
		let buff = UnsafeMutablePointer<UnsafePointer<Int8>?>.allocate(capacity:self.count + 1)
		buff.initialize(from:map { UnsafePointer<Int8>($0.withCString(strdup)) }, count:self.count)
		buff[self.count] = nil
		defer {
			for cur_arg in buff ..< buff + self.count {
				free(UnsafeMutableRawPointer(mutating:cur_arg.pointee))
			}
			buff.deallocate()
		}
		return try work(buff)
	}
}

enum tt_spawn_error:Error {
	case system_resource_stacksize_error
	case container_stack_allocation_error
	case system_func_clone_error
}

/* ---- primary spawn function ----
arguments:

 - path:			The path to the executable that will be launched as the `workload process`
 - arguments:		The command arguments that will be passed to the executable.
 - environment:		The environment variables that are to be assigned to the workload process before it launches
 - workingDirectory	The path to the directory that shall be assigned as the *working directory* of the process before it launches
 - stdin			The posix pipe that shall be *read* for data as the standard input for the workload process.
 - stdout			The posix pipe that shall be *written* to as the standard output for the workload process.
 - stderr			The posix pipe that shall be *written* to as the standard output for the workload process.
 - notify			The posix pipe that shall be *written* to as the workload process executes. Event flags are written to this pipe when various events happen with the process. These events include process launches, process exits, and data output line notifiers.
*/

public func tt_spawn(path:String, arguments:[String], environment:[String:String], workingDirectory:String, stdin:PosixSystemPipe?, stdout:PosixSystemPipe?, stderr:PosixSystemPipe?, notify:PosixSystemPipe) throws -> (process:pid_t, stack:UnsafeRawPointer) {
	//set up the tt_pipe that is used for the standard input channel
	var in_pipe:tt_pipe = tt_pipe() //default values are unknown, the initialized values are defined in the below if statement
	if stdin != nil {
		in_pipe.writing = stdin!.writing
		in_pipe.reading = stdin!.reading
	} else {
		in_pipe.writing = -1
		in_pipe.reading = -1
	}
	//set up the tt_pipe that is used for the standard output channel
	var out_pipe:tt_pipe = tt_pipe() //default values are unknown, the initialized values are defined in the below if statement
	if stdout != nil {
		out_pipe.writing = stdout!.writing
		out_pipe.reading = stdout!.reading
	} else {
		out_pipe.writing = -1
		out_pipe.reading = -1
	}
	//set up the tt_pipe that is used for the standard error channel
	var err_pipe:tt_pipe = tt_pipe() //default values are unknown, the initialized values are defined in the below if statement
	if stderr != nil {
		err_pipe.writing = stderr!.writing
		err_pipe.reading = stderr!.reading
	} else {
		err_pipe.writing = -1
		err_pipe.reading = -1
	}
	//set up the tt_pipe that is used for notifications
	var notify_pipe = tt_pipe()
	notify_pipe.writing = notify.writing
	notify_pipe.reading = notify.reading
	
	//call the tt_spawn_core c function
	let spawn_result:tt_spawn_result = environment.keys.as_c_array({ (env_keys) -> tt_spawn_result in
		return environment.values.as_c_array({ (env_values) -> tt_spawn_result in
			return arguments.as_c_array({ (proc_args) -> tt_spawn_result in
				return workingDirectory.withCString({ (wd) -> tt_spawn_result in
					return path.withCString({ (cpath) -> tt_spawn_result in
						return tt_spawn_core(cpath, proc_args, Int32(arguments.count), env_keys, env_values, Int32(environment.count), wd, in_pipe, out_pipe, err_pipe, notify_pipe)
					})
				})
			})
		})
	})
	
	switch spawn_result.launchResult {
		//handle all of the initial errors here
		case -2:
			throw tt_spawn_error.system_resource_stacksize_error
		case -3:
			throw tt_spawn_error.container_stack_allocation_error
		case -4:
			throw tt_spawn_error.system_func_clone_error
		default:
			//success
			return (process:spawn_result.launchResult, stack:UnsafeRawPointer(spawn_result.stackAllocation))
	}
}