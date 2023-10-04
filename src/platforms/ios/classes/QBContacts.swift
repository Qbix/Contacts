import Contacts
// import ContactsUI

@objc class QBContacts : NSObject {
    
    enum ErrorCodes:NSNumber {
        case UnsupportedAction = 1
        case WrongJsonObject = 2
        case PermissionDenied = 3
        case UnknownError = 10
        case NoContainers = 20
    }
    
    let store = CNContactStore()
    var linkedContactsDiscovered = false;
    private var linkedContacts = [String: [CNContact]]()
    private var linkedUnifiedContact = [String: CNContact]();
    
    @objc func hasPermission(
        completionHandler: @escaping (_ accessGranted: Bool) -> Void,
        requestIfNotAvailable: Bool = false
    ) {
        let store = CNContactStore();
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            completionHandler(true)
        case .denied:
            completionHandler(false)
        case .restricted, .notDetermined:
            if (requestIfNotAvailable) {
                store.requestAccess(for: .contacts) { granted, error in
                    if granted {
                        completionHandler(true)
                    } else {
                        DispatchQueue.main.async {
                            completionHandler(false)
                        }
                    }
                }
            } else {
                completionHandler(false)
            }
        }
    }
    
    private func keysToFetch() -> [CNKeyDescriptor] {
        let keysToFetch: [CNKeyDescriptor] = [
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactMiddleNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNamePrefixKey as CNKeyDescriptor,
            CNContactNameSuffixKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactDatesKey as CNKeyDescriptor,
            CNContactImageDataAvailableKey as CNKeyDescriptor,
            CNContactImageDataKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor
        ]
        return keysToFetch
    }
    
    @objc func allContainers(
        ids: [String]? = nil
    ) -> [CNContainer]?
    {
        var predicate : NSPredicate?;
        if (ids != nil) {
            predicate = CNContainer.predicateForContainers(withIdentifiers: ids!)
        }
        return try? store.containers(matching: predicate)
    }
    
    @objc func containerOfGroup(
        withIds groupId: String
    ) -> CNContainer? {
        var predicate = CNContainer.predicateForContainerOfGroup(withIdentifier: groupId);
        var containers = try? store.containers(matching: predicate)
        return containers?.first
    }
    
    @objc func containerOfContact(
        withId contactId: String
    ) -> CNContainer? {
        var predicate = CNContainer.predicateForContainerOfContact(withIdentifier: contactId);
        var containers = try? store.containers(matching: predicate)
        return containers?.first
    }
    
    @objc private func contacts(
        predicate: NSPredicate? = nil,
        sortOrder: CNContactSortOrder = .givenName,
        unifyResults: Bool = false,
        completion: @escaping ([CNContact]?, Error?) -> Void
    ) {
        self.hasPermission { (granted) in
            guard granted else {
                completion(nil, ErrorCodes.PermissionDenied as? Error)
                return
            }
        }
        let request = CNContactFetchRequest(keysToFetch: self.keysToFetch())
        request.unifyResults = unifyResults;
        request.predicate = predicate
        request.sortOrder = sortOrder
        DispatchQueue.global(qos: .userInitiated).async {
            var result = [CNContact]()
            do {
                try self.store.enumerateContacts(with: request)
                {(contact, status) -> Void in
                    result.append(contact)
                }
                if (predicate == nil) {
                    // store a cache for groupsFromContact
                }
                DispatchQueue.main.async {
                    completion(result, nil)
                }
            } catch let error as NSError {
                completion(nil, error)
            }
        }
    }

    @objc func allContacts(
        sortOrder: CNContactSortOrder = .givenName,
        unifyResults: Bool = false,
        completion: @escaping ([CNContact]?, Error?) -> Void
    ) {
        return contacts(predicate: nil,
                        sortOrder: sortOrder,
                        unifyResults: unifyResults,
                        completion: completion)
    }
    
    @objc func contactsFromContainer(
        containerId: String,
        sortOrder: CNContactSortOrder = .givenName,
        unifyResults: Bool = false,
        completion: @escaping (_ contacts: [CNContact]?, Error?) -> Void
    ) {
        let predicate = CNContact.predicateForContactsInContainer(withIdentifier: containerId)
        return contacts(predicate: predicate,
                        sortOrder: sortOrder,
                        unifyResults: unifyResults,
                        completion: completion)
    }
    
    @objc func contactsFromGroup(
        groupId: String,
        sortOrder: CNContactSortOrder = .givenName,
        unifyResults: Bool = false,
        completion: @escaping (_ contacts: [CNContact]?, Error?) -> Void
    ) {
        let predicate = CNContact.predicateForContactsInGroup(withIdentifier: groupId)
        return contacts(predicate: predicate,
                        sortOrder: sortOrder,
                        unifyResults: unifyResults,
                        completion: completion)
    }
    
    @objc func contactsByPhoneNumber(
        phoneNumber: CNPhoneNumber,
        completion: @escaping (_ contacts: [CNContact]?, Error?) -> Void
    ) {
        let predicate = CNContact.predicateForContacts(matching: phoneNumber)
        return contacts(predicate: predicate, sortOrder: .none, completion: completion)
    }
    
    @objc func contactsByEmailAddress(
        emailAddress: String,
        completion: @escaping (_ contacts: [CNContact]?, Error?) -> Void
    ) {
        let predicate = CNContact.predicateForContacts(matchingEmailAddress: emailAddress)
        return contacts(predicate: predicate, sortOrder: .none, completion: completion)
    }
    
    @objc func allUnifiedContacts(
        containerIds: [String]? = nil,
        sortOrder: CNContactSortOrder = .givenName,
        completion: @escaping ([CNContact]?, Error?) -> Void
    ) {
        self.hasPermission { (granted) in
            guard granted else {
                completion(nil, ErrorCodes.PermissionDenied as? Error)
                return
            }
        }
        let containers = self.allContainers(ids: containerIds)
        if (containers == nil) {
            completion(nil, ErrorCodes.NoContainers as? Error)
            return;
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var result = [CNContact]()
            do {
                for container in containers! {
                    let fetchPredicate = CNContact.predicateForContactsInContainer(
                        withIdentifier: container.identifier
                    )
                    let containerResults = try self.store.unifiedContacts(
                        matching: fetchPredicate,
                        keysToFetch: self.keysToFetch()
                    )
                    result.append(contentsOf: containerResults)
                }
                switch (sortOrder) {
                case .givenName:
                    result.sort{$0.givenName < $1.givenName}
                case .familyName:
                    result.sort{$0.familyName < $1.familyName}
                case .none:
                    result = result
                default:
                    result = result
                }
            } catch let error as NSError {
                completion(nil, error)
            }

            DispatchQueue.main.async {
                completion(result, nil)
            }
        }
    }

    @objc func contactById(
        id: String,
        unifyResults: Bool = false
    ) -> CNContact? {
        let request = CNContactFetchRequest(keysToFetch: self.keysToFetch())
        request.unifyResults = unifyResults;
        request.predicate = CNContact.predicateForContacts(withIdentifiers: [id]);
        request.sortOrder = .givenName
        var result : CNContact? = nil
        do {
            try self.store.enumerateContacts(with: request)
            {(contact, status) -> Void in
                result = contact;
            }
        } catch {
            result = nil;
        }
        return result;
    }

    @objc func unifiedContactById(
        id: String
    ) -> CNContact? {
        let keysToFetch = self.keysToFetch();
        let predicate = CNContact.predicateForContacts(withIdentifiers: [id]);
        let store = CNContactStore();
        do {
            let contacts = try store.unifiedContacts(
                matching: predicate,
                keysToFetch: keysToFetch
            );
            if (contacts.count == 1) {
                return contacts.first;
            }
            return nil;
        } catch {
            return nil;
        }
    }
    
    @objc func unifiedContactById(id: String) -> CNContact? {
        let keysToFetch = self.keysToFetch();
        let predicate = CNContact.predicateForContacts(withIdentifiers: [id]);
        let store = CNContactStore();
        do {
            let contacts = try store.unifiedContacts(
                matching: predicate,
                keysToFetch: keysToFetch
            );
            if (contacts.count == 1) {
                return contacts.first;
            }
            return nil;
        } catch {
            return nil;
        }
    }

    @objc func updateContact(
        contact: CNMutableContact,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        let saveRequest = CNSaveRequest()
        saveRequest.update(contact)
        do {
            try store.execute(saveRequest)
            completion(true, nil)
        } catch {
            completion(false, error)
        }
    }
    
    @objc func deleteContact(
        contact: CNContact,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        let mutableContact = contact.mutableCopy() as! CNMutableContact
        let saveRequest = CNSaveRequest()
        saveRequest.delete(mutableContact)
        do {
            try store.execute(saveRequest)
            completion(true, nil)
        } catch {
            completion(false, error)
        }
    }
    
    @objc func allGroups () -> [CNGroup] {
        do {
            return try store.groups(matching:nil);
        } catch {
            return [];
        }
    }
    
    @objc func groupsFromContact (
        contact: CNContact
    ) -> [CNGroup] {
        do {
            return try store.groups(matching:nil);
        } catch {
            return [];
        }
    }
    
    @objc func discoverLinkedContacts(
        completion: @escaping (Bool) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.allContacts(sortOrder:.givenName, unifyResults:true)
            { unified, err1 in
                self.allContacts(sortOrder:.givenName, unifyResults: false)
                { contacts, err2 in
                    if (contacts == nil) {
                        DispatchQueue.main.async {
                            completion(false)
                        }
                        return;
                    }
                    for u in unified! {
                        for c in contacts! {
                            if (c.isUnifiedWithContact(withIdentifier: u.identifier)) {
                                self.linkedUnifiedContact[c.identifier] = u;
                                let u_identifier = u.identifier;
                                if (self.linkedContacts[u_identifier] == nil) {
                                    self.linkedContacts[u_identifier] = []
                                }
                                self.linkedContacts[u_identifier]?.append(c)
                            }
                        }
                    }
                    DispatchQueue.main.async {
                        self.linkedContactsDiscovered = true;
                        completion(true);
                    }
                }
            }
        }
    }
    
    @objc func unifiedContactFromContactId(
        contactId: String
    ) -> CNContact? {
        if (!linkedContactsDiscovered) {
            return nil
        }
        return linkedUnifiedContact[contactId]
    }
    
    @objc func contactsFromUnifiedContact(
        contactId: String
    ) -> [CNContact] {
        if (!linkedContactsDiscovered || linkedContacts[contactId] == nil) {
            return [] // it must have been not a unified contract
        }
        return linkedContacts[contactId]! // return the linked contacts
    }

    @objc func addContactToGroup(
        contact: CNContact, // use contactsFromUnifiedContact first
        group: CNGroup,
        inContainerId: String? = nil,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        let addContactRequest = CNSaveRequest()
        let mutableContact : CNMutableContact = contact.mutableCopy() as! CNMutableContact
        addContactRequest.add(mutableContact, toContainerWithIdentifier: inContainerId)
        do {
            try store.execute(addContactRequest)
        } catch {}
        let addGroupRequest = CNSaveRequest()
        let mutableGroup : CNMutableGroup = group.mutableCopy() as! CNMutableGroup
        do {
            try store.execute(addGroupRequest)
            completion(true, nil)
        } catch {}
        addContactRequest.add(mutableGroup, toContainerWithIdentifier: inContainerId)
        let addMemberRequest = CNSaveRequest()
        addMemberRequest.addMember(mutableContact, to: mutableGroup);
        do {
            try store.execute(addMemberRequest)
            completion(true, nil)
        } catch {
            completion(false, error)
        }
    }

    @objc func removeContactFromGroup(
        contact: CNContact,
        group: CNGroup,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        let saveRequest = CNSaveRequest()
        saveRequest.removeMember(contact, from: group.mutableCopy() as! CNMutableGroup)

        do {
            try store.execute(saveRequest)
            completion(true, nil)
        } catch {
            completion(false, error)
        }
    }
    
    @objc func addGroup(
        group: CNGroup,
        toContainerId: String?,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        let saveRequest = CNSaveRequest()
        saveRequest.add(group.mutableCopy() as! CNMutableGroup,
                        toContainerWithIdentifier: toContainerId)
        do {
            try self.store.execute(saveRequest)
        } catch {
            completion(false, error);
        }
    }
    
    @objc func removeGroup(
        group: CNGroup,
        completion: @escaping (Bool, Error?) -> Void
    ) {
        let saveRequest = CNSaveRequest()
        saveRequest.delete(group.mutableCopy() as! CNMutableGroup)
        do {
            try self.store.execute(saveRequest)
        } catch {
            completion(false, error);
        }
    }
    
    // CONTACT PICKER
    
//    @objc func pick(
//        completion: @escaping (_ contacts: [CNContact]?, Error?) -> Void
//    ) {
//        self.hasPermission { (granted) in
//            guard granted else {
//                completion(nil, ErrorCodes.PermissionDenied as? Error)
//                return;
//            }
//            let contactPicker = CNContactPickerViewController();
//            contactPicker.delegate = self;
//            self.viewController?.present(contactPicker, animated: true, completion: nil)
//        }
//    }
//    
//    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
//        let fields: NSDictionary = [
//            "phoneNumbers": true,
//            "emails": true
//        ];
//        let options = ContactsXOptions(options: ["fields": fields]);
//        let contactResult = ContactX(contact: contact, options: options).getJson() as! [String : Any];
//        let result: CDVPluginResult = CDVPluginResult(status: CDVCommandStatus_OK, messageAs: contactResult);
//        self.commandDelegate.send(result, callbackId: self._callbackId);
//    }
}
