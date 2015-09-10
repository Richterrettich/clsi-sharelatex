SandboxedModule = require('sandboxed-module')
sinon = require('sinon')
require('chai').should()
modulePath = require('path').join __dirname, '../../../app/js/CompileController'
tk = require("timekeeper")

describe "CompileController", ->
	beforeEach ->
		@CompileController = SandboxedModule.require modulePath, requires:
			"./CompileManager": @CompileManager = {}
			"./RequestParser": @RequestParser = {}
			"settings-sharelatex": @Settings =
				apis:
					clsi:
						url: "http://clsi.example.com"
			"./ProjectPersistenceManager": @ProjectPersistenceManager = {}
			"logger-sharelatex": @logger = { log: sinon.stub(), error: sinon.stub() }
			"./Metrics": {
				Timer: class Timer
					done: sinon.stub()
			}
		@Settings.externalUrl = "http://www.example.com"
		@req = {}
		@res = {}
		@next = sinon.stub()

	describe "compile", ->
		beforeEach ->
			@req.body = {
				compile: "mock-body"
			}
			@req.params =
				project_id: @project_id = "project-id-123"
			@request = {
				compile: "mock-parsed-request"
			}
			@request_with_project_id =
				compile: @request.compile
				project_id: @project_id
			@output_files = [{
				path: "output.pdf"
				type: "pdf"
			}, {
				path: "output.log"
				type: "log"
			}]
			@output = {"mock":"output"}
			@RequestParser.parse = sinon.stub().callsArgWith(1, null, @request)
			@ProjectPersistenceManager.markProjectAsJustAccessed = sinon.stub().callsArg(1)
			@res.status = sinon.stub().returnsThis()
			@res.send = sinon.stub()

		describe "successfully", ->
			beforeEach ->
				@CompileManager.doCompile = sinon.stub().callsArgWith(1, null, @output_files, @output)
				@CompileController.compile @req, @res

			it "should parse the request", ->
				@RequestParser.parse
					.calledWith(@req.body)
					.should.equal true

			it "should run the compile for the specified project", ->
				@CompileManager.doCompile
					.calledWith(@request_with_project_id)
					.should.equal true

			it "should return the JSON response", ->
				@res.status.calledWith(200).should.equal true
				@res.send
					.calledWith(
						compile:
							status: "success"
							error: null
							outputFiles: @output_files.map (file) =>
								url: "#{@Settings.apis.clsi.url}/project/#{@project_id}/output/#{file.path}"
								type: file.type
							output: @output
					)
					.should.equal true
			
		describe "with an error", ->
			beforeEach ->
				@CompileManager.doCompile = sinon.stub().callsArgWith(1, new Error(@message = "error message"), null)
				@CompileController.compile @req, @res
		
			it "should return the JSON response with the error", ->
				@res.status.calledWith(500).should.equal true
				@res.send
					.calledWith(
						compile:
							status: "error"
							error:  @message
							outputFiles: []
							output: {}
					)
					.should.equal true

		describe "when the request times out", ->
			beforeEach ->
				@error = new Error(@message = "container timed out")
				@error.timedout = true
				@CompileManager.doCompile = sinon.stub().callsArgWith(1, @error, null)
				@CompileController.compile @req, @res
		
			it "should return the JSON response with the timeout status", ->
				@res.status.calledWith(200).should.equal true
				@res.send
					.calledWith(
						compile:
							status: "timedout"
							error: @message
							outputFiles: []
							output: {}
					)
					.should.equal true

	describe "stopCompile", ->
		beforeEach ->
			@CompileManager.stopCompile = sinon.stub().callsArg(2)
			@req.params =
				project_id: @project_id = "project-id-123"
				session_id: @session_id = "session-id-123"
			@res.send = sinon.stub()
			@CompileController.stopCompile @req, @res, @next

			it "should return the JSON response with the failure status", ->
				@res.status.calledWith(200).should.equal true
				@res.send
					.calledWith(
						compile:
							error: null
							status: "failure"
							outputFiles: []
					)
					.should.equal true

	describe "syncFromCode", ->
		beforeEach ->
			@file = "main.tex"
			@line = 42
			@column = 5
			@project_id = "mock-project-id"
			@req.params =
				project_id: @project_id
			@req.query =
				file: @file
				line: @line.toString()
				column: @column.toString()
			@res.send = sinon.stub()

			@CompileManager.syncFromCode = sinon.stub().callsArgWith(4, null, @pdfPositions = ["mock-positions"])
			@CompileController.syncFromCode @req, @res, @next

		it "should find the corresponding location in the PDF", ->
			@CompileManager.syncFromCode
				.calledWith(@project_id, @file, @line, @column)
				.should.equal true

		it "should return the positions", ->
			@res.send
				.calledWith(JSON.stringify
					pdf: @pdfPositions
				)
				.should.equal true

	describe "syncFromPdf", ->
		beforeEach ->
			@page = 5
			@h = 100.23
			@v = 45.67
			@project_id = "mock-project-id"
			@req.params =
				project_id: @project_id
			@req.query =
				page: @page.toString()
				h: @h.toString()
				v: @v.toString()
			@res.send = sinon.stub()

			@CompileManager.syncFromPdf = sinon.stub().callsArgWith(4, null, @codePositions = ["mock-positions"])
			@CompileController.syncFromPdf @req, @res, @next

		it "should find the corresponding location in the code", ->
			@CompileManager.syncFromPdf
				.calledWith(@project_id, @page, @h, @v)
				.should.equal true

		it "should return the positions", ->
			@res.send
				.calledWith(JSON.stringify
					code: @codePositions
				)
				.should.equal true

	describe "sendJupyterRequest", ->
		beforeEach ->
			@req.params =
				project_id: @project_id
			@req.body = {
				request_id: @request_id = "messsage-123"
				msg_type: @msg_type = "execute_request"
				content: @content = {mock: "content"}
				engine: @engine = "python"
				limits: @limits = {mock: "limits", timeout: 42}
				resources: @resources = ["mock", "resources"]
			}
			@res.sendStatus = sinon.stub()
			@CompileManager.sendJupyterRequest = sinon.stub().callsArg(7)
			@RequestParser.parseResources = sinon.stub().callsArgWith(1, null, @parsed_resources = ["parsed", "resources"])
			@CompileController.sendJupyterRequest @req, @res, @next
		
		it "should parse the resources", ->
			@RequestParser.parseResources
				.calledWith(@resources)
				.should.equal true
		
		it "should execute the request", ->
			@CompileManager.sendJupyterRequest
				.calledWith(@project_id, @parsed_resources, @request_id, @engine, @msg_type, @content, @limits)
				.should.equal true
		
		it "should convert the limits.timeout to millseconds", ->
			@limits.timeout.should.equal 42000
		
		it "should return 204", ->
			@res.sendStatus.calledWith(204).should.equal true
	
	describe "sendJupyterReply", ->
		beforeEach ->
			@req.params =
				project_id: @project_id
			@req.body = {
				msg_type: @msg_type = "input_reply"
				content: @content = {mock: "content"}
				engine: @engine = "python"
			}
			@res.sendStatus = sinon.stub()
			@CompileManager.sendJupyterReply = sinon.stub().callsArg(4)
			@CompileController.sendJupyterReply @req, @res, @next
		
		it "should execute the reply", ->
			@CompileManager.sendJupyterReply
				.calledWith(@project_id, @engine, @msg_type, @content)
				.should.equal true
		
		it "should return 204", ->
			@res.sendStatus.calledWith(204).should.equal true

	describe "interruptJupyterRequest", ->
		beforeEach ->
			@CompileManager.interruptJupyterRequest = sinon.stub().callsArg(2)
			@req.params =
				project_id: @project_id
				request_id: @request_id = "messsage-123"
			@res.sendStatus = sinon.stub()
			@CompileController.interruptJupyterRequest @req, @res, @next
		
		it "should interrupt the request", ->
			@CompileManager.interruptJupyterRequest
				.calledWith(@project_id, @request_id)
				.should.equal true
		
		it "should return 204", ->
			@res.sendStatus.calledWith(204).should.equal true
		
			
