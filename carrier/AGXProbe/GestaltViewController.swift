//
//  GestaltViewController.swift
//  Bench27
//
//  Edits the two About-screen fields the sandbox escape can reach: Model Name and
//  Model Number. Everything goes through the container extension; the serial
//  number and the device name are not reachable this way.
//

import UIKit

final class GestaltViewController: UIViewController, UITextFieldDelegate {

    private let statusLabel = UILabel()
    private let nameField = UITextField()
    private let numberField = UITextField()
    private let scroll = UIScrollView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background
        title = "Gestalt"

        let backdrop = MatrixBackdrop()
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let sub = UILabel()
        sub.text = "writes through the container extension ?? backup taken before every apply"
        sub.font = Theme.mono(10)
        sub.textColor = Theme.greenFaint
        sub.numberOfLines = 2

        statusLabel.font = Theme.mono(10)
        statusLabel.textColor = Theme.greenDim
        statusLabel.numberOfLines = 0
        statusLabel.text = "idle"

        configure(nameField, placeholder: "Model Name")
        configure(numberField, placeholder: "Model Number")

        let nameRow = fieldRow("Model Name", nameField)
        let numberRow = fieldRow("Model Number", numberField)

        let apply = button("Apply both", colour: UIColor(red: 0.10, green: 0.35, blue: 0.20, alpha: 1),
                           action: #selector(onApply))
        let restore = button("Restore backup", colour: Theme.surfaceHigh,
                             action: #selector(onRestore))
        let reload = button("Reload from cache", colour: Theme.surfaceHigh,
                            action: #selector(onReload))

        let stack = UIStackView(arrangedSubviews: [sub, statusLabel, nameRow, numberRow, apply, restore, reload])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Scroll view so the form moves with the keyboard and a drag closes it.
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.keyboardDismissMode = .interactive
        scroll.alwaysBounceVertical = true
        scroll.addSubview(stack)
        view.addSubview(scroll)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: g.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: g.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: g.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: g.bottomAnchor),

            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -40),
        ])

        // Tap anywhere outside the fields closes the keyboard.
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        scroll.addGestureRecognizer(tap)

        onReload()
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    private func configure(_ field: UITextField, placeholder: String) {
        field.placeholder = placeholder
        field.textColor = Theme.text
        field.font = Theme.mono(13)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .done
        field.delegate = self
        field.backgroundColor = Theme.surface
        field.layer.borderWidth = 1
        field.layer.borderColor = Theme.greenDim.withAlphaComponent(0.5).cgColor
        field.layer.cornerRadius = 8
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 1))
        field.leftViewMode = .always
        field.heightAnchor.constraint(equalToConstant: 40).isActive = true
        field.inputAccessoryView = doneToolbar()
    }

    private func doneToolbar() -> UIToolbar {
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        bar.barStyle = .black
        bar.items = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(dismissKeyboard)),
        ]
        bar.sizeToFit()
        return bar
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }

    private func fieldRow(_ label: String, _ field: UITextField) -> UIView {
        let l = UILabel()
        l.text = label
        l.font = .systemFont(ofSize: 12, weight: .semibold)
        l.textColor = Theme.textDim
        let s = UIStackView(arrangedSubviews: [l, field])
        s.axis = .vertical
        s.spacing = 6
        return s
    }

    private func button(_ title: String, colour: UIColor, action: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(Theme.green, for: .normal)
        b.layer.borderWidth = 1
        b.layer.borderColor = Theme.greenDim.withAlphaComponent(0.6).cgColor
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        b.backgroundColor = colour
        b.layer.cornerRadius = 10
        b.heightAnchor.constraint(equalToConstant: 44).isActive = true
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    // MARK: actions

    @objc private func onReload() {
        guard Escape.group != nil else {
            statusLabel.text = "no App Group ??? sign with the application-groups entitlement"
            return
        }
        let name = Escape.modelName() ?? "<unreadable>"
        let number = Escape.modelNumber() ?? "<unreadable>"
        nameField.text = name
        numberField.text = number
        statusLabel.text = "cache: Model Name = \(name) ?? Model Number = \(number)"
        Logger.shared.note("gestalt: loaded name=\(name) number=\(number)")
    }

    @objc private func onApply() {
        dismissKeyboard()
        let name = nameField.text ?? ""
        let number = numberField.text ?? ""
        guard !name.isEmpty || !number.isEmpty else {
            statusLabel.text = "nothing to apply"
            return
        }
        let backed = Escape.backupCache()
        guard backed else {
            statusLabel.text = "backup failed; no values were changed"
            Logger.shared.note("gestalt: apply aborted because backup failed")
            return
        }
        var done: [String] = []
        var failures: [String] = []

        if !name.isEmpty {
            let n = Escape.setModelName(name)
            if n > 0 { done.append("Model Name ??? \(name)") }
            else { failures.append("Model Name") }
        }
        if !number.isEmpty {
            if Escape.setModelNumber(number) {
                done.append("Model Number ??? \(number)")
            } else {
                failures.append("Model Number")
            }
        }

        if !failures.isEmpty {
            let restored = Escape.restoreCache()
            if restored {
                nameField.text = Escape.modelName() ?? "<unreadable>"
                numberField.text = Escape.modelNumber() ?? "<unreadable>"
            }
            statusLabel.text = restored
                ? "apply failed for \(failures.joined(separator: ", ")); original cache restored"
                : "apply failed for \(failures.joined(separator: ", ")); partial values may remain; restore backup"
            Logger.shared.note("gestalt: partial apply rolled back=\(restored), failures=\(failures.joined(separator: ", "))")
            return
        }

        statusLabel.text = done.isEmpty
            ? "nothing written ??? check the App Group and the cache path\nbackup saved"
            : (done.joined(separator: " ?? ") + "\nbackup saved")
        Logger.shared.note("gestalt: apply \(done.joined(separator: " | ")) backup=\(backed)")
    }

    @objc private func onRestore() {
        dismissKeyboard()
        let ok = Escape.restoreCache()
        statusLabel.text = ok ? "restored from the backup ??? restart Settings to see it"
                                : "no backup to restore"
        Logger.shared.note("gestalt: restore \(ok)")
        if ok { onReload() }
    }
}

