//
//  P2PConflictResolutionTest.swift
//  CBL_EE_Swift
//
//  Created by Pasin Suriyentrakorn on 6/23/20.
//  Copyright © 2020 Couchbase. All rights reserved.
//

import Foundation

@testable import CouchbaseLiteSwift

@available(macOS 10.12, iOS 10.0, *)
class P2PConflictResolutionTest: ReplicatorTest {
    
    func testScenario1() throws {
        // Setup:
        // db1 (db1Repl) <-> (sg1Listener) sg1 <-> (db2Repl) db2
        
        Database.log.console.level = .info
        Database.log.console.domains = .replicator
        
        Database.log.console.level = .info
        Database.log.console.domains = .replicator
        
        try deleteDB(name: "db1")
        let db1 = try openDB(name: "db1")
        
        try deleteDB(name: "db2")
        let db2 = try openDB(name: "db2")
        
        try deleteDB(name: "sg1")
        let sg1 = try openDB(name: "sg1")
        
        let config1 = URLEndpointListenerConfiguration(database: sg1)
        config1.disableTLS = true
        config1.port = 5000
        let sg1Listener = URLEndpointListener(config: config1)
        try sg1Listener.start()
        
        let db1ReplConfig = ReplicatorConfiguration(database: db1, target: sg1Listener.localURLEndpoint)
        db1ReplConfig.conflictResolver = DelayConflictResolver.init(name: "DB1-Resolver", delay: 5.0)
        db1ReplConfig.continuous = true
        let db1Repl = Replicator.init(config: db1ReplConfig)
        
        let db2ReplConfig = ReplicatorConfiguration(database: db2, target: sg1Listener.localURLEndpoint)
        db2ReplConfig.conflictResolver = DelayConflictResolver.init(name: "DB2-Resolver", delay: 5.0)
        db2ReplConfig.continuous = true
        let db2Repl = Replicator.init(config: db2ReplConfig)
        
        db1Repl.start()
        db2Repl.start()
        
        // Create doc and replicator to all dbs:
        let doc1 = MutableDocument.init(id: "doc1")
        doc1.setString("tiger", forKey: "name")
        try db1.saveDocument(doc1)
        
        wait { () -> Bool in
            let a = db1.document(withID: "doc1") != nil
            let b = db2.document(withID: "doc1") != nil
            let c = sg1.document(withID: "doc1") != nil
            return a && b && c
        }
        
        // Stop db2Repl:
        db2Repl.stop()
        wait { () -> Bool in
            return db2Repl.status.activity == .stopped
        }
        
        // Update docs and make conflict:
        
        // Update doc on DB1
        let doc1a = db1.document(withID: "doc1")!.toMutable()
        doc1a.setString("cat", forKey: "name")
        try db1.saveDocument(doc1a)
        
        // Update doc on DB2
        let doc1b = db2.document(withID: "doc1")!.toMutable()
        doc1b.setString("lion", forKey: "name")
        try db2.saveDocument(doc1b)
        
        wait { () -> Bool in
            let rev1 = sg1.document(withID: "doc1")!.revisionID!
            return rev1.hasPrefix("2-")
        }
        
        // Check current state:
        print("<---------- BEFORE UPDATED DOCS TO REPLICATE ---------->")
        var rev1 = db1.document(withID: "doc1")!.revisionID!
        var rev2 = db2.document(withID: "doc1")!.revisionID!
        var rev3 = sg1.document(withID: "doc1")!.revisionID!
        print(">>>>>>>DB1 REV: \(rev1)")
        print(">>>>>>>SG1 REV: \(rev3)")
        print(">>>>>>>DB2 REV: \(rev2)")
        var a = db1.document(withID: "doc1")!.string(forKey: "name")!
        var b = db2.document(withID: "doc1")!.string(forKey: "name")!
        var c = sg1.document(withID: "doc1")!.string(forKey: "name")!
        print(">>>>>>> DB1 DOC: \(a)")
        print(">>>>>>> SG1 DOC: \(c)")
        print(">>>>>>> DB2 DOC: \(b)")
        
        // Start db2Repl:
        db2Repl.start()
        
        var i = 0
        wait { () -> Bool in
            i = i + 1
            let a = db1.document(withID: "doc1")!.string(forKey: "name")!
            let b = db2.document(withID: "doc1")!.string(forKey: "name")!
            let c = sg1.document(withID: "doc1")!.string(forKey: "name")!
            print("<---------- WAIT FOR DOCS TO REPLICATE (#\(i)) ---------->")
            print("WAIT >>>>>>> DB1 DOC: \(a)")
            print("WAIT >>>>>>> SG1 DOC: \(c)")
            print("WAIT >>>>>>> DB2 DOC: \(b)")
            return (a == b) && (b == c)
        }
        
        print("<---------- AFTER UPDATED DOCS REPLICATED ---------->")
        rev1 = db1.document(withID: "doc1")!.revisionID!
        rev2 = db2.document(withID: "doc1")!.revisionID!
        rev3 = sg1.document(withID: "doc1")!.revisionID!
        print(">>>>>>> DB1 REV: \(rev1)")
        print(">>>>>>> SG1 REV: \(rev3)")
        print(">>>>>>> DB2 REV: \(rev2)")
        a = db1.document(withID: "doc1")!.string(forKey: "name")!
        b = db2.document(withID: "doc1")!.string(forKey: "name")!
        c = sg1.document(withID: "doc1")!.string(forKey: "name")!
        print(">>>>>>> DB1 DOC: \(a)")
        print(">>>>>>> DB2 DOC: \(b)")
        print(">>>>>>> SG1 DOC: \(c)")
        
        wait { () -> Bool in
            return db1Repl.status.activity == .idle &&
                   db2Repl.status.activity == .idle
        }
        
        sg1Listener.stop()
        db1Repl.stop()
        db2Repl.stop()
        
        wait { () -> Bool in
            let a = db1Repl.status.activity == .stopped
            let b = db2Repl.status.activity == .stopped
            return a && b
        }
        
        try db1.delete()
        try db2.delete()
        try sg1.delete()
    }
    
    func testScenario2() throws {
        // Setup:
        // db1 (db1Repl) <-> (sg1Listener) sg1 (sg1Repl) <-> (sg2Listener) sg2
        
        Database.log.console.level = .debug
        Database.log.console.domains = .all
        
        try deleteDB(name: "db1")
        let db1 = try openDB(name: "db1")
        
        try deleteDB(name: "sg1")
        let sg1 = try openDB(name: "sg1")
        
        try deleteDB(name: "sg2")
        let sg2 = try openDB(name: "sg2")
        
        let config1 = URLEndpointListenerConfiguration(database: sg1)
        config1.disableTLS = true
        config1.port = 5000
        let sg1Listener = URLEndpointListener(config: config1)
        try sg1Listener.start()
        
        let config2 = URLEndpointListenerConfiguration(database: sg2)
        config2.disableTLS = true
        config2.port = 6000
        let sg2Listener = URLEndpointListener(config: config2)
        try sg2Listener.start()
        
        let db1ReplConfig = ReplicatorConfiguration(database: db1, target: sg1Listener.localURLEndpoint)
        db1ReplConfig.conflictResolver = DelayConflictResolver.init(name: "DB1-Resolver", delay: 5.0)
        db1ReplConfig.continuous = true
        let db1Repl = Replicator.init(config: db1ReplConfig)
        
        let sg1ReplConfig = ReplicatorConfiguration(database: sg1, target: sg2Listener.localURLEndpoint)
        sg1ReplConfig.conflictResolver = DelayConflictResolver.init(name: "SG1-Resolver", delay: 5.0)
        sg1ReplConfig.continuous = true
        let sg1Repl = Replicator.init(config: sg1ReplConfig)
        
        db1Repl.start()
        sg1Repl.start()
        
        // Create doc and replicator to all dbs:
        let doc1 = MutableDocument.init(id: "doc1")
        doc1.setString("tiger", forKey: "name")
        try db1.saveDocument(doc1)
        
        wait { () -> Bool in
            let a = db1.document(withID: "doc1") != nil
            let b = sg1.document(withID: "doc1") != nil
            let c = sg2.document(withID: "doc1") != nil
            return a && b && c
        }
        
        // Stop sg1 <-> sg2 replication:
        sg1Repl.stop()
        wait { () -> Bool in
            return sg1Repl.status.activity == .stopped
        }
        
        // Update doc on DB1
        let doc1a = db1.document(withID: "doc1")!.toMutable()
        doc1a.setString("cat", forKey: "name")
        try db1.saveDocument(doc1a)
        
        // Update doc on SG2
        let doc1b = sg2.document(withID: "doc1")!.toMutable()
        doc1b.setString("lion", forKey: "name")
        try sg2.saveDocument(doc1b)
        
        wait { () -> Bool in
            let rev1 = sg1.document(withID: "doc1")!.revisionID!
            let rev2 = sg2.document(withID: "doc1")!.revisionID!
            let a = rev1.hasPrefix("2-")
            let b = rev2.hasPrefix("2-")
            return a && b
        }
        
        // Check current state:
        print("<---------- BEFORE UPDATED DOCS TO REPLICATE ---------->")
        var rev1 = db1.document(withID: "doc1")!.revisionID!
        var rev2 = sg1.document(withID: "doc1")!.revisionID!
        var rev3 = sg2.document(withID: "doc1")!.revisionID!
        print(">>>>>>>DB1 REV: \(rev1)")
        print(">>>>>>>SG1 REV: \(rev2)")
        print(">>>>>>>SG2 REV: \(rev3)")
        var a = db1.document(withID: "doc1")!.string(forKey: "name")!
        var b = sg1.document(withID: "doc1")!.string(forKey: "name")!
        var c = sg2.document(withID: "doc1")!.string(forKey: "name")!
        print(">>>>>>> DB1 DOC: \(a)")
        print(">>>>>>> SG1 DOC: \(b)")
        print(">>>>>>> SG2 DOC: \(c)")
        
        // Start sg1-sg2 replication again:
        
        sg1Repl.start()
        
        var i = 0
        wait { () -> Bool in
            i = i + 1
            let a = db1.document(withID: "doc1")!.string(forKey: "name")!
            let b = sg1.document(withID: "doc1")!.string(forKey: "name")!
            let c = sg2.document(withID: "doc1")!.string(forKey: "name")!
            print("<---------- WAIT FOR DOCS TO REPLICATE (#\(i)) ---------->")
            print("WAIT >>>>>>> DB1 DOC: \(a)")
            print("WAIT >>>>>>> SG1 DOC: \(b)")
            print("WAIT >>>>>>> SG2 DOC: \(c)")
            
            if a  == c && b != c {
                assert(false, "DB1 got a conflicted doc from SG1 before the conflict has been resolved!!")
            }
            
            return (a == b) && (b == c)
        }
        
        print("<---------- AFTER UPDATED DOCS REPLICATED ---------->")
        rev1 = db1.document(withID: "doc1")!.revisionID!
        rev2 = sg1.document(withID: "doc1")!.revisionID!
        rev3 = sg2.document(withID: "doc1")!.revisionID!
        print(">>>>>>> DB1 REV: \(rev1)")
        print(">>>>>>> SG1 REV: \(rev2)")
        print(">>>>>>> SG2 REV: \(rev3)")
        a = db1.document(withID: "doc1")!.string(forKey: "name")!
        b = sg1.document(withID: "doc1")!.string(forKey: "name")!
        c = sg2.document(withID: "doc1")!.string(forKey: "name")!
        print(">>>>>>> DB1 DOC: \(a)")
        print(">>>>>>> SG1 DOC: \(b)")
        print(">>>>>>> SG2 DOC: \(c)")
        
        wait { () -> Bool in
            return db1Repl.status.activity == .idle &&
                   sg1Repl.status.activity == .idle
        }
        
        sg1Listener.stop()
        sg2Listener.stop()
        
        db1Repl.stop()
        sg1Repl.stop()
        
        wait { () -> Bool in
            let a = db1Repl.status.activity == .stopped
            let b = sg1Repl.status.activity == .stopped
            return a && b
        }
        
        try db1.delete()
        try sg1.delete()
        try sg2.delete()
    }
    
    func testScenario3() throws {
        // Setup:
        // db1 (db1Repl) <-> (sg1Listener) sg1 (sg1Repl) <-> (sg2Listener) sg2 <-> (db2Repl) db2
        
        Database.log.console.level = .info
        Database.log.console.domains = .replicator
        
        try deleteDB(name: "db1")
        let db1 = try openDB(name: "db1")
        
        try deleteDB(name: "db2")
        let db2 = try openDB(name: "db2")
        
        try deleteDB(name: "sg1")
        let sg1 = try openDB(name: "sg1")
        
        try deleteDB(name: "sg2")
        let sg2 = try openDB(name: "sg2")
        
        let config1 = URLEndpointListenerConfiguration(database: sg1)
        config1.disableTLS = true
        config1.port = 5000
        let sg1Listener = URLEndpointListener(config: config1)
        try sg1Listener.start()
        
        let config2 = URLEndpointListenerConfiguration(database: sg2)
        config2.disableTLS = true
        config2.port = 6000
        let sg2Listener = URLEndpointListener(config: config2)
        try sg2Listener.start()
        
        let db1ReplConfig = ReplicatorConfiguration(database: db1, target: sg1Listener.localURLEndpoint)
        db1ReplConfig.conflictResolver = DelayConflictResolver.init(name: "DB1-Resolver", delay: 5.0)
        db1ReplConfig.continuous = true
        let db1Repl = Replicator.init(config: db1ReplConfig)
        
        let db2ReplConfig = ReplicatorConfiguration(database: db2, target: sg2Listener.localURLEndpoint)
        db2ReplConfig.conflictResolver = DelayConflictResolver.init(name: "DB2-Resolver", delay: 5.0)
        db2ReplConfig.continuous = true
        let db2Repl = Replicator.init(config: db2ReplConfig)
        
        let sg1ReplConfig = ReplicatorConfiguration(database: sg1, target: sg2Listener.localURLEndpoint)
        sg1ReplConfig.conflictResolver = DelayConflictResolver.init(name: "SG1-Resolver", delay: 5.0)
        sg1ReplConfig.continuous = true
        let sg1Repl = Replicator.init(config: sg1ReplConfig)
        
        db1Repl.start()
        db2Repl.start()
        sg1Repl.start()
        
        // Create doc and replicator to all dbs:
        let doc1 = MutableDocument.init(id: "doc1")
        doc1.setString("tiger", forKey: "name")
        try db1.saveDocument(doc1)
        
        wait { () -> Bool in
            let a = db1.document(withID: "doc1") != nil
            let b = db2.document(withID: "doc1") != nil
            let c = sg1.document(withID: "doc1") != nil
            let d = sg2.document(withID: "doc1") != nil
            return a && b && c && d
        }
        
        // Stop sg1 <-> sg2 replication:
        sg1Repl.stop()
        wait { () -> Bool in
            return sg1Repl.status.activity == .stopped
        }
        
        // Update doc on DB1
        let doc1a = db1.document(withID: "doc1")!.toMutable()
        doc1a.setString("cat", forKey: "name")
        try db1.saveDocument(doc1a)
        
        // Update doc on DB2
        let doc1b = db2.document(withID: "doc1")!.toMutable()
        doc1b.setString("lion", forKey: "name")
        try db2.saveDocument(doc1b)
        
        wait { () -> Bool in
            let rev1 = sg1.document(withID: "doc1")!.revisionID!
            let rev2 = sg2.document(withID: "doc1")!.revisionID!
            let a = rev1.hasPrefix("2-")
            let b = rev2.hasPrefix("2-")
            return a && b
        }
        
        // Check current state:
        print("<---------- BEFORE UPDATED DOCS TO REPLICATE ---------->")
        var rev1 = db1.document(withID: "doc1")!.revisionID!
        var rev2 = db2.document(withID: "doc1")!.revisionID!
        var rev3 = sg1.document(withID: "doc1")!.revisionID!
        var rev4 = sg2.document(withID: "doc1")!.revisionID!
        print(">>>>>>>DB1 REV: \(rev1)")
        print(">>>>>>>SG1 REV: \(rev3)")
        print(">>>>>>>SG2 REV: \(rev4)")
        print(">>>>>>>DB2 REV: \(rev2)")
        var a = db1.document(withID: "doc1")!.string(forKey: "name")!
        var b = db2.document(withID: "doc1")!.string(forKey: "name")!
        var c = sg1.document(withID: "doc1")!.string(forKey: "name")!
        var d = sg2.document(withID: "doc1")!.string(forKey: "name")!
        print(">>>>>>> DB1 DOC: \(a)")
        print(">>>>>>> SG1 DOC: \(c)")
        print(">>>>>>> SG2 DOC: \(d)")
        print(">>>>>>> DB2 DOC: \(b)")
        
        // Start sg1-sg2 replication again:
        sg1Repl.start()
        
        var i = 0
        wait { () -> Bool in
            i = i + 1
            let a = db1.document(withID: "doc1")!.string(forKey: "name")!
            let b = db2.document(withID: "doc1")!.string(forKey: "name")!
            let c = sg1.document(withID: "doc1")!.string(forKey: "name")!
            let d = sg2.document(withID: "doc1")!.string(forKey: "name")!
            print("<---------- WAIT FOR DOCS TO REPLICATE (#\(i)) ---------->")
            print("WAIT >>>>>>> DB1 DOC: \(a)")
            print("WAIT >>>>>>> SG1 DOC: \(c)")
            print("WAIT >>>>>>> SG2 DOC: \(d)")
            print("WAIT >>>>>>> DB2 DOC: \(b)")
            return (a == b) && (b == c) && (c == d)
        }
        
        print("<---------- AFTER UPDATED DOCS REPLICATED ---------->")
        rev1 = db1.document(withID: "doc1")!.revisionID!
        rev2 = db2.document(withID: "doc1")!.revisionID!
        rev3 = sg1.document(withID: "doc1")!.revisionID!
        rev4 = sg2.document(withID: "doc1")!.revisionID!
        print(">>>>>>> DB1 REV: \(rev1)")
        print(">>>>>>> SG1 REV: \(rev3)")
        print(">>>>>>> SG2 REV: \(rev4)")
        print(">>>>>>> DB2 REV: \(rev2)")
        a = db1.document(withID: "doc1")!.string(forKey: "name")!
        b = db2.document(withID: "doc1")!.string(forKey: "name")!
        c = sg1.document(withID: "doc1")!.string(forKey: "name")!
        d = sg2.document(withID: "doc1")!.string(forKey: "name")!
        print(">>>>>>> DB1 DOC: \(a)")
        print(">>>>>>> DB2 DOC: \(b)")
        print(">>>>>>> SG1 DOC: \(c)")
        print(">>>>>>> SG2 DOC: \(d)")
        
        wait { () -> Bool in
            return db1Repl.status.activity == .idle &&
                   db2Repl.status.activity == .idle &&
                   sg1Repl.status.activity == .idle
        }
        
        sg1Listener.stop()
        sg2Listener.stop()
        
        db1Repl.stop()
        db2Repl.stop()
        sg1Repl.stop()
        
        wait { () -> Bool in
            let a = db1Repl.status.activity == .stopped
            let b = db2Repl.status.activity == .stopped
            let c = sg1Repl.status.activity == .stopped
            return a && b && c
        }
        
        try db1.delete()
        try db2.delete()
        try sg1.delete()
        try sg2.delete()
    }

    func wait(for something: @escaping () -> Bool) {
        while (!something()) {
            RunLoop.current.run(mode: .default, before: Date.init(timeIntervalSinceNow: 1.0))
        }
    }
    
    class DelayConflictResolver: ConflictResolverProtocol {
        let name: String
        let delay: TimeInterval
        
        init(name: String, delay: TimeInterval) {
            self.name = name
            self.delay = delay
        }
        
        func resolve(conflict: Conflict) -> Document? {
            var resolved = false
            var resolvedDoc: Document? = nil
            
            // If remote and local have same generation and both are not deleted, return remote:
            if let remote = conflict.remoteDocument, let local = conflict.localDocument {
                let revID1 = remote.revisionID!
                let revID2 = local.revisionID!
                
                let gen1 = revID1[..<revID1.firstIndex(of: "-")!]
                let gen2 = revID2[..<revID2.firstIndex(of: "-")!]
                
                if gen1 == gen2 {
                    resolved = true
                    resolvedDoc = remote
                }
            }
            
            if !resolved {
                resolvedDoc = ConflictResolver.default.resolve(conflict: conflict)
            }
            
            if delay > 0 {
                Thread.sleep(forTimeInterval: delay)
            }
            
            if let r = resolvedDoc {
                print(">>>>>>> RESOLVED BY \(name): \(r.revisionID!)")
            } else {
                print(">>>>>>> RESOLVED BY \(name): DELETED")
            }
            
            return resolvedDoc
        }
    }
}



