RequestParser = require "./RequestParser"
CompileManager = require "./CompileManager"
Settings = require "settings-sharelatex"
Metrics = require "./Metrics"
ProjectPersistenceManager = require "./ProjectPersistenceManager"
logger = require "logger-sharelatex"

module.exports = CompileController =
	compile: (req, res, next = (error) ->) ->
		timer = new Metrics.Timer("compile-request")
		RequestParser.parse req.body, (error, request) ->
			return next(error) if error?
			request.project_id = req.params.project_id
			CompileManager.doCompile request, (error, outputFiles = [], output = {}) ->
				if error?
					logger.error err: error, project_id: request.project_id, "error running compile"
					if error.timedout
						status = "timedout"
					else
						status = "error"
						code = 500
				else
					status = "success"

				timer.done()
				res.status(code or 200).send {
					compile:
						status: status
						error:  error?.message or error
						outputFiles: outputFiles.map (file) ->
							url: "#{Settings.apis.clsi.url}/project/#{request.project_id}/output/#{file.path}"
							type: file.type
						output: output
				}
	
	stopCompile: (req, res, next) ->
		{project_id, session_id} = req.params
		CompileManager.stopCompile project_id, session_id, (error) ->
			return next(error) if error?
			res.sendStatus(204)

	listFiles: (req, res, next) ->
		{project_id} = req.params
		CompileManager.listFiles project_id, (error, outputFiles) ->
			if error?
				code = 500
			res.status(code or 200).send {
				outputFiles: outputFiles.map (file) ->
							url: "#{Settings.apis.clsi.url}/project/#{project_id}/output/#{file.path}"
							name: "#{file.path}"
							type: file.type
			}

	deleteFile: (req, res, next) ->
		{project_id, file} = req.params
		CompileManager.deleteFile project_id, file, (error) ->
			return next(error) if error?
			res.sendStatus(204)

	sendJupyterRequest: (req, res, next) ->
		{project_id} = req.params
		{request_id, msg_type, content, limits, engine, resources} = req.body
		RequestParser.parseResources resources, (error, resources) ->
			return next(error) if error?
			if limits.timeout?
				limits.timeout = limits.timeout * 1000 # Request is in seconds, internally we use ms
			CompileManager.sendJupyterRequest project_id, resources, request_id, engine, msg_type, content, limits, (error) ->
				return next(error) if error?
				res.sendStatus(204)
	
	interruptJupyterRequest: (req, res, next) ->
		{project_id, request_id} = req.params
		CompileManager.interruptJupyterRequest project_id, request_id, (error) ->
			return next(error) if error?
			res.sendStatus(204)
		
	clearCache: (req, res, next = (error) ->) ->
		ProjectPersistenceManager.clearProject req.params.project_id, (error) ->
			return next(error) if error?
			res.sendStatus(204) # No content

	syncFromCode: (req, res, next = (error) ->) ->
		file   = req.query.file
		line   = parseInt(req.query.line, 10)
		column = parseInt(req.query.column, 10)
		project_id = req.params.project_id

		CompileManager.syncFromCode project_id, file, line, column, (error, pdfPositions) ->
			return next(error) if error?
			res.send JSON.stringify {
				pdf: pdfPositions
			}

	syncFromPdf: (req, res, next = (error) ->) ->
		page   = parseInt(req.query.page, 10)
		h      = parseFloat(req.query.h)
		v      = parseFloat(req.query.v)
		project_id = req.params.project_id

		CompileManager.syncFromPdf project_id, page, h, v, (error, codePositions) ->
			return next(error) if error?
			res.send JSON.stringify {
				code: codePositions
			}
