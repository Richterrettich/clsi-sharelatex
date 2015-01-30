UrlCache = require "./UrlCache"
db = require "./db"
async = require "async"
logger = require "logger-sharelatex"
FilesystemManager = require "./FilesystemManager"
CommandRunner = require "./CommandRunner"
Settings = require "settings-sharelatex"

module.exports = ProjectPersistenceManager =
	EXPIRY_TIMEOUT: Settings.clsi?.expireProjectAfterIdleMs or 6 * 60 * 60 * 1000 # 6 hours

	markProjectAsJustAccessed: (project_id, callback = (error) ->) ->
		db.Project.findOrCreate(project_id: project_id)
			.success(
				(project) ->
					project.updateAttributes(lastAccessed: new Date())
						.success(() -> callback())
						.error callback
			)
			.error callback

	clearExpiredProjects: (callback = (error) ->) ->
		ProjectPersistenceManager._findExpiredProjectIds (error, project_ids) ->
			return callback(error) if error?
			logger.log project_ids: project_ids, "clearing expired projects"
			jobs = for project_id in (project_ids or [])
				do (project_id) ->
					(callback) ->
						ProjectPersistenceManager.clearProject project_id, (err) ->
							if err?
								logger.error err: err, project_id: project_id, "error clearing project"
							callback()
			async.series jobs, callback

	clearProject: (project_id, callback = (error) ->) ->
		logger.log project_id: project_id, "clearing project"
		CommandRunner.clearProject project_id, (error) ->
			return callback(error) if error?
			FilesystemManager.clearProject project_id, (error) ->
				return callback(error) if error?
				UrlCache.clearProject project_id, (error) ->
					return callback(error) if error?
					ProjectPersistenceManager._clearProjectFromDatabase project_id, (error) ->
						return callback(error) if error?
						callback()

	_clearProjectFromDatabase: (project_id, callback = (error) ->) ->
		db.Project.destroy(project_id: project_id)
			.success(() -> callback())
			.error callback

	_findExpiredProjectIds: (callback = (error, project_ids) ->) ->
		db.Project.findAll(where: ["lastAccessed < ?", new Date(Date.now() - ProjectPersistenceManager.EXPIRY_TIMEOUT)])
			.success(
				(projects) ->
					callback null, projects.map((project) -> project.project_id)
			)
			.error callback
