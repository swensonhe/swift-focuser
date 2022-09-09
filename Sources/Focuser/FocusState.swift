//
//  File.swift
//  
//
//  Created by Tarek Sabry on 09/09/2022.
//

import Combine
import SwiftUI

extension View {
    public func focused<T>(file: StaticString = #file, _ state: FocusState<T>, equals value: T) -> some View {
        modifier(FocusedModifier(state: state, id: value, file: file))
    }
}

@propertyWrapper
public struct FocusState<T: Hashable>: DynamicProperty {
    @State var value = CurrentValueSubject<T?, Never>(nil)

    public var wrappedValue: T? {
        get { value.value }
        nonmutating set { value.value = newValue }
    }
    public var projectedValue: FocusState<T> { self }

    public init(wrappedValue: T?) {
        self.value.value = wrappedValue
    }
}

private struct FocusedModifier<T: Hashable>: ViewModifier {
    @State private var item: Focusable?
    let state: FocusState<T>
    let id: T
    let file: StaticString
    
    @State private var observer = TextFieldObserver()
    
    var hashValue: Int {
        return "\(id):\(file)".hashValue
    }
    private func isFocusable(_ view: UIView) -> Bool {
        return view.canBecomeFirstResponder && view is Focusable
    }

    func body(content: Content) -> some View {
        content
            .onWillDisappear {
                updateState(nil)
            }
            .discover(tag: hashValue, where: isFocusable) { (view: UIView) in
                item = (view as! Focusable)
                item!.focused {
                    updateState(state.wrappedValue)
                }
                updateResponder(state.wrappedValue)
                
                if let textField = view as? UITextField {
                    if !(textField.delegate is TextFieldObserver) {
                        observer.forwardToDelegate = textField.delegate
                        textField.delegate = observer
                    }
                }
                
                observer.onReturnTap = {
                    updateResponder(state.wrappedValue)
                }
            }
            .onReceive(state.value, perform: updateResponder)
    }

    private func updateResponder(_ value: T?) {
        if value == id, item?.isFirstResponder == false {
            item?.becomeFirstResponder()
        } else if value != id, item?.isFirstResponder == true {
            item?.resignFirstResponder()
        }
    }
    private func updateState(_ value: T?) {
        if item?.isFirstResponder == true, value != id {
            state.wrappedValue = id
        } else if item?.isFirstResponder == false, value == id, UIApplication.shared.firstResponder == nil {
            state.wrappedValue = nil
        }
    }
}

private protocol Focusable: UIView {
    func focused(_ closure: @escaping () -> Void)
}
extension UIControl: Focusable {
    func focused(_ closure: @escaping () -> Void) {
        let handler: UIActionHandler = { _ in
            DispatchQueue.main.async { closure() }
        }
        addAction(.init(handler: handler), for: .allEditingEvents)
    }
}
extension UITextView: Focusable {
    func focused(_ closure: @escaping () -> Void) {
        var subscription: AnyCancellable?
        subscription = Publishers.MergeMany([
            NotificationCenter.default.publisher(for: UITextView.textDidChangeNotification, object: self),
            NotificationCenter.default.publisher(for: UITextView.textDidEndEditingNotification, object: self),
            NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification, object: self),
        ])
        .sink(
            receiveCompletion: { _ in subscription?.cancel() },
            receiveValue: { _ in closure() }
        )
    }
}

private var _firstResponder: UIResponder?

private extension UIApplication {
    var firstResponder: UIResponder? {
        _firstResponder = nil
        sendAction(#selector(UIResponder.updateFirstResponder), to: nil, from: nil, for: nil)
        return _firstResponder
    }
}

private extension UIResponder {
    @objc func updateFirstResponder() {
        _firstResponder = self
    }
}
