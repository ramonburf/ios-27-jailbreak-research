//
//  PlacesViewController.swift
//  Bench27
//
//  The entry point of the file manager: the container classes the escape can
//  reach, each with what the measurement says about them.
//

import UIKit

final class PlacesViewController: UITableViewController, UISearchResultsUpdating {

    private let results = SearchResultsController(style: .plain)
    private lazy var search: UISearchController = {
        let c = UISearchController(searchResultsController: results)
        c.searchResultsUpdater = self
        c.obscuresBackgroundDuringPresentation = false
        c.searchBar.placeholder = ""
        c.searchBar.tintColor = Theme.green
        c.searchBar.searchTextField.backgroundColor = Theme.surface
        c.searchBar.searchTextField.textColor = Theme.text
        return c
    }()

    func updateSearchResults(for searchController: UISearchController) {
        results.search(searchController.searchBar.text ?? "")
    }

    private struct Place {
        let title: String
        let path: String
        let note: String
        let writable: Bool
    }

    private lazy var places: [Place] = [
        Place(title: "SystemGroup",
              path: "/private/var/containers/Shared/SystemGroup",
              note: "shared system groups ?? read and write",
              writable: true),
        Place(title: "Application",
              path: "/private/var/mobile/Containers/Data/Application",
              note: "other apps' sandboxes ?? read and write",
              writable: true),
        Place(title: "AppGroup",
              path: "/private/var/mobile/Containers/Shared/AppGroup",
              note: "app group containers ?? read and write",
              writable: true),
        Place(title: "InternalDaemon",
              path: "/private/var/mobile/Containers/Data/InternalDaemon",
              note: "daemon containers ?? read and write",
              writable: true),
        Place(title: "PluginKitPlugin",
              path: "/private/var/mobile/Containers/Data/PluginKitPlugin",
              note: "plug-in containers ?? read and write",
              writable: true),
        Place(title: "Data/System",
              path: "/private/var/containers/Data/System",
              note: "system container ?? read only",
              writable: false),
        Place(title: "This app",
              path: NSHomeDirectory(),
              note: "our own container ?? for comparison",
              writable: true),
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Files"
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        tableView.backgroundColor = Theme.background
        tableView.separatorColor = Theme.greenDim.withAlphaComponent(0.25)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.tableFooterView = UIView()
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72

    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        places.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let p = places[indexPath.row]
        var c = cell.defaultContentConfiguration()
        c.image = UIImage(systemName: p.writable ? "folder.fill" : "folder")
        c.imageProperties.tintColor = p.writable ? Theme.green : Theme.greenDim
        c.imageProperties.maximumSize = CGSize(width: 24, height: 24)
        // The path is the name; the only annotation is what the grant allows.
        c.text = p.path.replacingOccurrences(of: "/private", with: "")
        c.secondaryText = p.writable ? "read and write" : "read only"
        c.textProperties.color = Theme.text
        c.textProperties.font = Theme.sans(13.5, .medium)
        c.textProperties.numberOfLines = 2
        c.textProperties.lineBreakMode = .byTruncatingMiddle
        c.secondaryTextProperties.color = p.writable ? Theme.green : Theme.textFaint
        c.secondaryTextProperties.font = Theme.sans(11)
        cell.contentConfiguration = c
        cell.backgroundColor = Theme.surface
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let p = places[indexPath.row]
        navigationController?.pushViewController(FilesViewController(path: p.path), animated: true)
    }
}

