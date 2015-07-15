UrlCache = require "./UrlCache"
Path = require "path"
fs = require "fs"
async = require "async"
OutputFileFinder = require "./OutputFileFinder"
Metrics = require "./Metrics"
FilesystemManager = require "./FilesystemManager"

module.exports = ResourceWriter =
	syncResourcesToDisk: (project_id, resources, callback = (error) ->) ->
		@_removeExtraneousFiles project_id, resources, (error) =>
			return callback(error) if error?
			@_writeResourcesToDisk(project_id, resources, callback)

	_removeExtraneousFiles: (project_id, resources, _callback = (error) ->) ->
		timer = new Metrics.Timer("unlink-output-files")
		callback = (error) ->
			timer.done()
			_callback(error)

		OutputFileFinder.findOutputFiles project_id, resources, (error, outputFiles) ->
			return callback(error) if error?

			jobs = []
			for file in outputFiles or []
				do (file) ->
					path = file.path
					console.log "will delete", path
					jobs.push (callback) ->
						FilesystemManager.deleteFileIfNotDirectory project_id, path, callback

			async.series jobs, (error) ->
				return callback(error) if error?
				FilesystemManager.deleteEmptyDirectories project_id, callback

	_writeResourcesToDisk: (project_id, resources, callback = (error) ->) ->
		async.mapSeries resources,
			(resource, callback) ->
				if resource.url?
					UrlCache.getPathOnDisk project_id, resource.url, resource.modified, (error, pathOnDisk) ->
						return callback(error) if error?
						callback null, {
							path: resource.path
							src:  pathOnDisk
						}
				else
					callback null, {
						path:    resource.path
						content: resource.content
					}
			(error, files) ->
				return callback(error) if error?
				FilesystemManager.addFiles project_id, files, callback


