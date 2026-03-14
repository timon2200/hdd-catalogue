import Foundation
import SwiftUI
import SwiftData

/// Centralized undo/redo manager for HDD Catalogue.
/// Wraps Foundation.UndoManager and provides typed helpers for each undoable action.
@Observable
final class UndoManagerService {
    let undoManager = UndoManager()
    
    // MARK: - Project Edit Undo
    
    struct ProjectSnapshot {
        let displayName: String
        let projectType: String
        let aiSummary: String
        let isEdited: Bool
        let clientId: UUID?
    }
    
    func registerProjectEdit(
        project: Project,
        oldSnapshot: ProjectSnapshot,
        newSnapshot: ProjectSnapshot,
        context: ModelContext
    ) {
        undoManager.registerUndo(withTarget: self) { [weak self] service in
            project.displayName = oldSnapshot.displayName
            project.projectType = oldSnapshot.projectType
            project.aiSummary = oldSnapshot.aiSummary
            project.isEdited = oldSnapshot.isEdited
            
            // Restore client relationship
            if let clientId = oldSnapshot.clientId {
                let descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientId })
                project.client = try? context.fetch(descriptor).first
            } else {
                project.client = nil
            }
            
            try? context.save()
            
            // Register redo
            self?.registerProjectEdit(
                project: project,
                oldSnapshot: newSnapshot,
                newSnapshot: oldSnapshot,
                context: context
            )
        }
        undoManager.setActionName("Edit Project")
    }
    
    // MARK: - Thumbnail Change Undo
    
    struct ThumbnailSnapshot {
        let thumbnailTypeRaw: String
        let thumbnailData: Data?
        let thumbnailEmoji: String?
        let thumbnailIconName: String?
    }
    
    func registerThumbnailChange(
        project: Project,
        oldSnapshot: ThumbnailSnapshot,
        newSnapshot: ThumbnailSnapshot,
        context: ModelContext
    ) {
        undoManager.registerUndo(withTarget: self) { [weak self] service in
            project.thumbnailTypeRaw = oldSnapshot.thumbnailTypeRaw
            project.thumbnailData = oldSnapshot.thumbnailData
            project.thumbnailEmoji = oldSnapshot.thumbnailEmoji
            project.thumbnailIconName = oldSnapshot.thumbnailIconName
            try? context.save()
            
            self?.registerThumbnailChange(
                project: project,
                oldSnapshot: newSnapshot,
                newSnapshot: oldSnapshot,
                context: context
            )
        }
        undoManager.setActionName("Change Thumbnail")
    }
    
    // MARK: - Project Deletion Undo
    
    struct DeletedProjectSnapshot {
        let project: Project
        let driveId: UUID?
        let clientId: UUID?
        let duplicateGroupId: UUID?
    }
    
    func registerProjectDeletion(
        snapshot: DeletedProjectSnapshot,
        context: ModelContext
    ) {
        undoManager.registerUndo(withTarget: self) { [weak self] service in
            // Re-insert the project
            context.insert(snapshot.project)
            
            // Restore relationships
            if let driveId = snapshot.driveId {
                let descriptor = FetchDescriptor<Drive>(predicate: #Predicate { $0.id == driveId })
                snapshot.project.drive = try? context.fetch(descriptor).first
            }
            if let clientId = snapshot.clientId {
                let descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientId })
                snapshot.project.client = try? context.fetch(descriptor).first
            }
            if let groupId = snapshot.duplicateGroupId {
                let descriptor = FetchDescriptor<DuplicateGroup>(predicate: #Predicate { $0.id == groupId })
                snapshot.project.duplicateGroup = try? context.fetch(descriptor).first
            }
            
            try? context.save()
            
            // Register redo (re-delete)
            self?.registerProjectRedeletion(project: snapshot.project, snapshot: snapshot, context: context)
        }
        undoManager.setActionName("Delete Project")
    }
    
    private func registerProjectRedeletion(
        project: Project,
        snapshot: DeletedProjectSnapshot,
        context: ModelContext
    ) {
        undoManager.registerUndo(withTarget: self) { [weak self] service in
            let redoSnapshot = DeletedProjectSnapshot(
                project: project,
                driveId: project.drive?.id,
                clientId: project.client?.id,
                duplicateGroupId: project.duplicateGroup?.id
            )
            context.delete(project)
            try? context.save()
            self?.registerProjectDeletion(snapshot: redoSnapshot, context: context)
        }
        undoManager.setActionName("Delete Project")
    }
    
    // MARK: - Drive Deletion Undo
    
    func registerDriveDeletion(
        drive: Drive,
        projects: [Project],
        context: ModelContext
    ) {
        // Capture project snapshots before deletion
        let projectSnapshots: [(project: Project, clientId: UUID?, groupId: UUID?)] = projects.map {
            ($0, $0.client?.id, $0.duplicateGroup?.id)
        }
        
        undoManager.registerUndo(withTarget: self) { [weak self] service in
            // Re-insert drive
            context.insert(drive)
            
            // Re-insert all projects and restore relationships
            for snapshot in projectSnapshots {
                context.insert(snapshot.project)
                snapshot.project.drive = drive
                
                if let clientId = snapshot.clientId {
                    let descriptor = FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientId })
                    snapshot.project.client = try? context.fetch(descriptor).first
                }
                if let groupId = snapshot.groupId {
                    let descriptor = FetchDescriptor<DuplicateGroup>(predicate: #Predicate { $0.id == groupId })
                    snapshot.project.duplicateGroup = try? context.fetch(descriptor).first
                }
            }
            
            try? context.save()
            
            // Register redo
            self?.registerDriveRedeletion(drive: drive, context: context)
        }
        undoManager.setActionName("Delete Drive")
    }
    
    private func registerDriveRedeletion(drive: Drive, context: ModelContext) {
        undoManager.registerUndo(withTarget: self) { [weak self] service in
            let projects = drive.projects
            let projectSnapshots: [(project: Project, clientId: UUID?, groupId: UUID?)] = projects.map {
                ($0, $0.client?.id, $0.duplicateGroup?.id)
            }
            context.delete(drive)
            try? context.save()
            self?.registerDriveDeletion(drive: drive, projects: projectSnapshots.map(\.project), context: context)
        }
        undoManager.setActionName("Delete Drive")
    }
    
    // MARK: - Client Deletion Undo
    
    func registerClientDeletion(
        client: Client,
        projectIds: [UUID],
        context: ModelContext
    ) {
        undoManager.registerUndo(withTarget: self) { [weak self] service in
            // Re-insert client
            context.insert(client)
            
            // Re-assign projects
            for projectId in projectIds {
                let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
                if let project = try? context.fetch(descriptor).first {
                    project.client = client
                }
            }
            
            try? context.save()
            
            // Register redo
            self?.registerClientRedeletion(client: client, context: context)
        }
        undoManager.setActionName("Delete Client")
    }
    
    private func registerClientRedeletion(client: Client, context: ModelContext) {
        undoManager.registerUndo(withTarget: self) { [weak self] service in
            let projectIds = client.projects.map(\.id)
            context.delete(client)
            try? context.save()
            self?.registerClientDeletion(client: client, projectIds: projectIds, context: context)
        }
        undoManager.setActionName("Delete Client")
    }
    
    // MARK: - Duplicate Dismissal Undo
    
    func registerDismissal(
        group: DuplicateGroup,
        context: ModelContext
    ) {
        undoManager.registerUndo(withTarget: self) { [weak self] service in
            group.isDismissed = false
            try? context.save()
            
            // Register redo
            self?.registerUndismissal(group: group, context: context)
        }
        undoManager.setActionName("Dismiss Duplicate")
    }
    
    private func registerUndismissal(group: DuplicateGroup, context: ModelContext) {
        undoManager.registerUndo(withTarget: self) { [weak self] service in
            group.isDismissed = true
            try? context.save()
            self?.registerDismissal(group: group, context: context)
        }
        undoManager.setActionName("Dismiss Duplicate")
    }
    
    func registerDismissAll(
        groups: [DuplicateGroup],
        context: ModelContext
    ) {
        undoManager.registerUndo(withTarget: self) { [weak self] service in
            for group in groups {
                group.isDismissed = false
            }
            try? context.save()
            
            self?.registerRedismissAll(groups: groups, context: context)
        }
        undoManager.setActionName("Dismiss All Duplicates")
    }
    
    private func registerRedismissAll(groups: [DuplicateGroup], context: ModelContext) {
        undoManager.registerUndo(withTarget: self) { [weak self] service in
            for group in groups {
                group.isDismissed = true
            }
            try? context.save()
            self?.registerDismissAll(groups: groups, context: context)
        }
        undoManager.setActionName("Dismiss All Duplicates")
    }
    
    // MARK: - Client Edit Undo (rename / recolor)
    
    struct ClientSnapshot {
        let name: String
        let colorHex: String
    }
    
    func registerClientEdit(
        client: Client,
        oldSnapshot: ClientSnapshot,
        newSnapshot: ClientSnapshot,
        context: ModelContext
    ) {
        undoManager.registerUndo(withTarget: self) { [weak self] service in
            client.name = oldSnapshot.name
            client.colorHex = oldSnapshot.colorHex
            try? context.save()
            
            self?.registerClientEdit(
                client: client,
                oldSnapshot: newSnapshot,
                newSnapshot: oldSnapshot,
                context: context
            )
        }
        undoManager.setActionName("Edit Client")
    }
    
    // MARK: - Client Merge Undo
    
    func registerClientMerge(
        deletedClient: Client,
        targetClient: Client,
        movedProjectIds: [UUID],
        context: ModelContext
    ) {
        undoManager.registerUndo(withTarget: self) { [weak self] service in
            // Re-insert the deleted (source) client
            context.insert(deletedClient)
            
            // Move projects back to the source client
            for projectId in movedProjectIds {
                let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
                if let project = try? context.fetch(descriptor).first {
                    project.client = deletedClient
                }
            }
            
            try? context.save()
            
            // Register redo
            self?.registerClientRemerge(
                sourceClient: deletedClient,
                targetClient: targetClient,
                projectIds: movedProjectIds,
                context: context
            )
        }
        undoManager.setActionName("Merge Clients")
    }
    
    private func registerClientRemerge(
        sourceClient: Client,
        targetClient: Client,
        projectIds: [UUID],
        context: ModelContext
    ) {
        undoManager.registerUndo(withTarget: self) { [weak self] service in
            // Move projects back to target
            for projectId in projectIds {
                let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == projectId })
                if let project = try? context.fetch(descriptor).first {
                    project.client = targetClient
                }
            }
            
            context.delete(sourceClient)
            try? context.save()
            
            self?.registerClientMerge(
                deletedClient: sourceClient,
                targetClient: targetClient,
                movedProjectIds: projectIds,
                context: context
            )
        }
        undoManager.setActionName("Merge Clients")
    }
}
